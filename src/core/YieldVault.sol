// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title YieldVault V1 — ERC-4626 vault, UUPS upgradeable, Pausable
/// @dev Simulates yield by allowing a YIELD_MANAGER to inject tokens into the vault,
///      increasing the share price for all depositors (totalAssets grows).
contract YieldVaultV1 is
    Initializable,
    ERC20Upgradeable,
    ERC4626Upgradeable,
    PausableUpgradeable,
    AccessControlUpgradeable,
    UUPSUpgradeable
{
    using SafeERC20 for IERC20;

    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant YIELD_MANAGER_ROLE = keccak256("YIELD_MANAGER_ROLE");
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");

    uint256 public constant MAX_DEPOSIT_PER_TX = 1_000_000e18;

    event YieldInjected(address indexed by, uint256 amount);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address underlyingAsset,
        string memory name_,
        string memory symbol_,
        address admin
    ) external initializer {
        __ERC20_init(name_, symbol_);
        __ERC4626_init(IERC20(underlyingAsset));
        __Pausable_init();
        __AccessControl_init();

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(PAUSER_ROLE, admin);
        _grantRole(YIELD_MANAGER_ROLE, admin);
        _grantRole(UPGRADER_ROLE, admin);
    }

    // ─── Pausing ─────────────────────────────────────────────────────────────
    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    // ─── Yield injection ──────────────────────────────────────────────────────
    /// @notice Inject external yield into the vault (increases share price)
    function injectYield(uint256 amount) external onlyRole(YIELD_MANAGER_ROLE) {
        SafeERC20.safeTransferFrom(IERC20(asset()), msg.sender, address(this), amount);
        emit YieldInjected(msg.sender, amount);
    }

    // ─── ERC-4626 overrides with pause guard ──────────────────────────────────
    function deposit(uint256 assets, address receiver)
        public
        override
        whenNotPaused
        returns (uint256)
    {
        require(assets <= MAX_DEPOSIT_PER_TX, "YieldVault: deposit too large");
        return super.deposit(assets, receiver);
    }

    function mint(uint256 shares, address receiver)
        public
        override
        whenNotPaused
        returns (uint256)
    {
        return super.mint(shares, receiver);
    }

    function withdraw(uint256 assets, address receiver, address owner_)
        public
        override
        whenNotPaused
        returns (uint256)
    {
        return super.withdraw(assets, receiver, owner_);
    }

    function redeem(uint256 shares, address receiver, address owner_)
        public
        override
        whenNotPaused
        returns (uint256)
    {
        return super.redeem(shares, receiver, owner_);
    }

    // ─── Required OZ v5 overrides ─────────────────────────────────────────────
    // ERC4626Upgradeable does not override _update in OZ v5, so only ERC20Upgradeable needed.
    function _update(address from, address to, uint256 value)
        internal
        override(ERC20Upgradeable)
    {
        super._update(from, to, value);
    }

    function decimals()
        public
        view
        override(ERC20Upgradeable, ERC4626Upgradeable)
        returns (uint8)
    {
        return super.decimals();
    }

    function _authorizeUpgrade(address newImplementation)
        internal
        override
        onlyRole(UPGRADER_ROLE)
    {}
}

/// @title YieldVault V2 — adds a fee-on-yield feature to demonstrate upgrade path
contract YieldVaultV2 is YieldVaultV1 {
    uint256 public constant VERSION = 2;
    uint256 public performanceFee; // basis points, e.g. 500 = 5%
    address public feeRecipient;

    event PerformanceFeeSet(uint256 fee, address recipient);

    function setPerformanceFee(uint256 fee, address recipient) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(fee <= 3000, "YieldVaultV2: fee > 30%");
        performanceFee = fee;
        feeRecipient = recipient;
        emit PerformanceFeeSet(fee, recipient);
    }

    function injectYieldWithFee(uint256 amount) external onlyRole(YIELD_MANAGER_ROLE) {
        uint256 fee = (amount * performanceFee) / 10_000;
        uint256 net = amount - fee;
        SafeERC20.safeTransferFrom(IERC20(asset()), msg.sender, address(this), amount);
        if (fee > 0 && feeRecipient != address(0)) {
            SafeERC20.safeTransfer(IERC20(asset()), feeRecipient, fee);
        }
        emit YieldInjected(msg.sender, net);
    }

    function version() external pure returns (string memory) {
        return "2.0.0";
    }
}
