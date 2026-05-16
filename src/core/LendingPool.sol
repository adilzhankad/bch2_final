// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "./PriceOracle.sol";

/// @title LendingPool — collateral-backed lending with health factor, liquidation, linear interest
contract LendingPool is ReentrancyGuard, AccessControl {
    using SafeERC20 for IERC20;

    bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");

    // ─── Asset config ────────────────────────────────────────────────────────
    struct AssetConfig {
        PriceOracle oracle;
        uint256 ltv;            // 1e18 = 100%, e.g. 0.75e18 = 75%
        uint256 liquidationThreshold; // e.g. 0.80e18
        uint256 liquidationBonus;     // e.g. 0.05e18
        bool isCollateral;
        bool isBorrowable;
    }

    // ─── User position ────────────────────────────────────────────────────────
    struct UserPosition {
        uint256 collateralAmount;
        uint256 debtAmount;
        uint256 debtAccruedAt; // block.timestamp when debt was last updated
    }

    // ─── Interest model ──────────────────────────────────────────────────────
    // Linear: rate = baseRate + utilization * slope
    uint256 public constant BASE_RATE = 0.02e18;  // 2% annual base
    uint256 public constant RATE_SLOPE = 0.20e18; // 20% annual at 100% utilization
    uint256 public constant SECONDS_PER_YEAR = 365 days;
    uint256 public constant LIQUIDATION_CLOSE_FACTOR = 0.5e18; // can repay up to 50%
    uint256 public constant HEALTH_FACTOR_MIN = 1e18;

    mapping(address => AssetConfig) public assetConfig;
    // collateralToken => borrowToken => user => position
    mapping(address => mapping(address => mapping(address => UserPosition))) public positions;
    mapping(address => uint256) public totalDeposited;
    mapping(address => uint256) public totalBorrowed;

    event Deposited(address indexed user, address indexed token, uint256 amount);
    event Withdrawn(address indexed user, address indexed token, uint256 amount);
    event Borrowed(address indexed user, address indexed collateral, address indexed debt, uint256 amount);
    event Repaid(address indexed user, address indexed collateral, address indexed debt, uint256 amount);
    event Liquidated(address indexed liquidator, address indexed user, address indexed collateral, address debt, uint256 debtRepaid, uint256 collateralSeized);
    event AssetConfigured(address indexed token, uint256 ltv, bool isCollateral, bool isBorrowable);

    error AssetNotConfigured();
    error NotCollateral();
    error NotBorrowable();
    error InsufficientCollateral();
    error BorrowExceedsLTV();
    error HealthFactorOK();
    error HealthFactorTooLow();
    error InsufficientLiquidity();
    error ZeroAmount();

    constructor(address admin) {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(MANAGER_ROLE, admin);
    }

    // ─── Admin ────────────────────────────────────────────────────────────────
    function configureAsset(
        address token,
        address oracle,
        uint256 ltv,
        uint256 liquidationThreshold,
        uint256 liquidationBonus,
        bool isCollateral,
        bool isBorrowable
    ) external onlyRole(MANAGER_ROLE) {
        require(ltv <= liquidationThreshold, "LendingPool: ltv > threshold");
        require(liquidationThreshold < 1e18, "LendingPool: threshold >= 100%");
        assetConfig[token] = AssetConfig({
            oracle: PriceOracle(oracle),
            ltv: ltv,
            liquidationThreshold: liquidationThreshold,
            liquidationBonus: liquidationBonus,
            isCollateral: isCollateral,
            isBorrowable: isBorrowable
        });
        emit AssetConfigured(token, ltv, isCollateral, isBorrowable);
    }

    // ─── Deposit collateral ───────────────────────────────────────────────────
    function deposit(address token, uint256 amount) external nonReentrant {
        if (amount == 0) revert ZeroAmount();
        AssetConfig storage cfg = assetConfig[token];
        if (cfg.oracle == PriceOracle(address(0))) revert AssetNotConfigured();
        if (!cfg.isCollateral) revert NotCollateral();

        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        totalDeposited[token] += amount;
        emit Deposited(msg.sender, token, amount);
    }

    // ─── Provide liquidity (borrowable tokens) ────────────────────────────────
    /// @notice Lenders supply borrowable tokens to earn interest
    function depositLiquidity(address token, uint256 amount) external nonReentrant {
        if (amount == 0) revert ZeroAmount();
        AssetConfig storage cfg = assetConfig[token];
        if (cfg.oracle == PriceOracle(address(0))) revert AssetNotConfigured();
        if (!cfg.isBorrowable) revert NotBorrowable();

        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        totalDeposited[token] += amount;
        emit Deposited(msg.sender, token, amount);
    }

    // ─── Borrow ───────────────────────────────────────────────────────────────
    function borrow(
        address collateralToken,
        uint256 collateralAmount,
        address debtToken,
        uint256 borrowAmount
    ) external nonReentrant {
        if (borrowAmount == 0 || collateralAmount == 0) revert ZeroAmount();
        AssetConfig storage colCfg = assetConfig[collateralToken];
        AssetConfig storage debtCfg = assetConfig[debtToken];
        if (colCfg.oracle == PriceOracle(address(0))) revert AssetNotConfigured();
        if (debtCfg.oracle == PriceOracle(address(0))) revert AssetNotConfigured();
        if (!colCfg.isCollateral) revert NotCollateral();
        if (!debtCfg.isBorrowable) revert NotBorrowable();

        uint256 colPrice = colCfg.oracle.getPrice();
        uint256 debtPrice = debtCfg.oracle.getPrice();
        uint256 colValueUSD = (collateralAmount * colPrice) / 1e18;
        uint256 maxBorrowUSD = (colValueUSD * colCfg.ltv) / 1e18;
        uint256 borrowValueUSD = (borrowAmount * debtPrice) / 1e18;
        if (borrowValueUSD > maxBorrowUSD) revert BorrowExceedsLTV();
        if (totalDeposited[debtToken] < totalBorrowed[debtToken] + borrowAmount) revert InsufficientLiquidity();

        // CEI: update state then transfer
        IERC20(collateralToken).safeTransferFrom(msg.sender, address(this), collateralAmount);
        UserPosition storage pos = positions[collateralToken][debtToken][msg.sender];
        _accrueInterest(pos, debtToken);
        pos.collateralAmount += collateralAmount;
        pos.debtAmount += borrowAmount;
        totalBorrowed[debtToken] += borrowAmount;

        IERC20(debtToken).safeTransfer(msg.sender, borrowAmount);
        emit Borrowed(msg.sender, collateralToken, debtToken, borrowAmount);
    }

    // ─── Repay ────────────────────────────────────────────────────────────────
    function repay(address collateralToken, address debtToken, uint256 repayAmount)
        external
        nonReentrant
        returns (uint256 collateralReturned)
    {
        if (repayAmount == 0) revert ZeroAmount();
        UserPosition storage pos = positions[collateralToken][debtToken][msg.sender];
        _accrueInterest(pos, debtToken);
        if (repayAmount > pos.debtAmount) repayAmount = pos.debtAmount;

        // CEI: transfer in, update state, transfer out
        IERC20(debtToken).safeTransferFrom(msg.sender, address(this), repayAmount);
        pos.debtAmount -= repayAmount;
        totalBorrowed[debtToken] -= repayAmount;

        // Return collateral proportional to the fraction of debt repaid.
        // Math: collateral_returned = collateral * repayAmount / debtBefore
        // where debtBefore = pos.debtAmount (already reduced) + repayAmount.
        // This keeps health factor unchanged after a partial repay.
        if (pos.debtAmount == 0) {
            collateralReturned = pos.collateralAmount;
            pos.collateralAmount = 0;
        } else {
            uint256 debtBefore = pos.debtAmount + repayAmount;
            collateralReturned = (pos.collateralAmount * repayAmount) / debtBefore;
            pos.collateralAmount -= collateralReturned;
        }
        if (collateralReturned > 0) {
            IERC20(collateralToken).safeTransfer(msg.sender, collateralReturned);
        }
        emit Repaid(msg.sender, collateralToken, debtToken, repayAmount);
    }

    // ─── Withdraw free collateral ─────────────────────────────────────────────
    function withdrawCollateral(address collateralToken, address debtToken, uint256 amount)
        external
        nonReentrant
    {
        if (amount == 0) revert ZeroAmount();
        UserPosition storage pos = positions[collateralToken][debtToken][msg.sender];
        _accrueInterest(pos, debtToken);
        require(pos.collateralAmount >= amount, "LendingPool: insufficient collateral");

        // Check health factor after withdrawal
        uint256 remainingCollateral = pos.collateralAmount - amount;
        if (pos.debtAmount > 0) {
            uint256 hf = _healthFactor(collateralToken, debtToken, remainingCollateral, pos.debtAmount);
            if (hf < HEALTH_FACTOR_MIN) revert HealthFactorTooLow();
        }
        pos.collateralAmount -= amount;
        IERC20(collateralToken).safeTransfer(msg.sender, amount);
        emit Withdrawn(msg.sender, collateralToken, amount);
    }

    // ─── Internal helper ─────────────────────────────────────────────────────
    function _calcCollateralSeized(address collateralToken, address debtToken, uint256 debtToCover)
        internal
        view
        returns (uint256)
    {
        uint256 colPrice = assetConfig[collateralToken].oracle.getPrice();
        uint256 debtPrice = assetConfig[debtToken].oracle.getPrice();
        uint256 debtValueUSD = (debtToCover * debtPrice) / 1e18;
        uint256 colValueToSeize = (debtValueUSD * (1e18 + assetConfig[collateralToken].liquidationBonus)) / 1e18;
        return (colValueToSeize * 1e18) / colPrice;
    }

    // ─── Liquidate ────────────────────────────────────────────────────────────
    function liquidate(
        address collateralToken,
        address debtToken,
        address borrower,
        uint256 debtToCover
    ) external nonReentrant {
        if (debtToCover == 0) revert ZeroAmount();
        UserPosition storage pos = positions[collateralToken][debtToken][borrower];
        _accrueInterest(pos, debtToken);

        uint256 hf = _healthFactor(collateralToken, debtToken, pos.collateralAmount, pos.debtAmount);
        if (hf >= HEALTH_FACTOR_MIN) revert HealthFactorOK();

        // Max repay is 50% close factor
        uint256 maxRepay = (pos.debtAmount * LIQUIDATION_CLOSE_FACTOR) / 1e18;
        if (debtToCover > maxRepay) debtToCover = maxRepay;

        // Collateral seized = debtValue * (1 + bonus) / colPrice
        uint256 collateralSeized = _calcCollateralSeized(collateralToken, debtToken, debtToCover);
        if (collateralSeized > pos.collateralAmount) collateralSeized = pos.collateralAmount;

        // CEI: state update before transfers
        pos.debtAmount -= debtToCover;
        pos.collateralAmount -= collateralSeized;
        totalBorrowed[debtToken] -= debtToCover;

        IERC20(debtToken).safeTransferFrom(msg.sender, address(this), debtToCover);
        IERC20(collateralToken).safeTransfer(msg.sender, collateralSeized);

        emit Liquidated(msg.sender, borrower, collateralToken, debtToken, debtToCover, collateralSeized);
    }

    // ─── Interest accrual ─────────────────────────────────────────────────────
    function _accrueInterest(UserPosition storage pos, address debtToken) internal {
        if (pos.debtAmount == 0 || pos.debtAccruedAt == 0) {
            pos.debtAccruedAt = block.timestamp;
            return;
        }
        uint256 elapsed = block.timestamp - pos.debtAccruedAt;
        if (elapsed == 0) return;
        uint256 rate = _borrowRate(debtToken);
        uint256 interest = (pos.debtAmount * rate * elapsed) / (1e18 * SECONDS_PER_YEAR);
        pos.debtAmount += interest;
        pos.debtAccruedAt = block.timestamp;
    }

    function _borrowRate(address debtToken) internal view returns (uint256) {
        uint256 deposited = totalDeposited[debtToken];
        if (deposited == 0) return BASE_RATE;
        uint256 utilization = (totalBorrowed[debtToken] * 1e18) / deposited;
        return BASE_RATE + (utilization * RATE_SLOPE) / 1e18;
    }

    function _healthFactor(
        address collateralToken,
        address debtToken,
        uint256 collateralAmount,
        uint256 debtAmount
    ) internal view returns (uint256) {
        if (debtAmount == 0) return type(uint256).max;
        AssetConfig storage colCfg = assetConfig[collateralToken];
        AssetConfig storage debtCfg = assetConfig[debtToken];
        uint256 colPrice = colCfg.oracle.getPrice();
        uint256 debtPrice = debtCfg.oracle.getPrice();
        uint256 colValueUSD = (collateralAmount * colPrice) / 1e18;
        uint256 adjustedCollateral = (colValueUSD * colCfg.liquidationThreshold) / 1e18;
        uint256 debtValueUSD = (debtAmount * debtPrice) / 1e18;
        return (adjustedCollateral * 1e18) / debtValueUSD;
    }

    function healthFactor(address collateralToken, address debtToken, address user)
        external
        view
        returns (uint256)
    {
        UserPosition storage pos = positions[collateralToken][debtToken][user];
        return _healthFactor(collateralToken, debtToken, pos.collateralAmount, pos.debtAmount);
    }

    function borrowRate(address debtToken) external view returns (uint256) {
        return _borrowRate(debtToken);
    }
}
