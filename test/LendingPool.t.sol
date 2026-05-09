// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/core/LendingPool.sol";
import "../src/core/PriceOracle.sol";
import "../src/core/MockAggregatorV3.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockToken is ERC20 {
    constructor(string memory n, string memory s) ERC20(n, s) {}
    function mint(address to, uint256 amount) external { _mint(to, amount); }
}

contract LendingPoolTest is Test {
    LendingPool internal lending;
    MockToken internal collToken;
    MockToken internal debtToken;
    PriceOracle internal collOracle;
    PriceOracle internal debtOracle;
    MockAggregatorV3 internal collFeed;
    MockAggregatorV3 internal debtFeed;

    address internal admin = makeAddr("admin");
    address internal alice = makeAddr("alice");
    address internal lender = makeAddr("lender");
    address internal liquidator = makeAddr("liquidator");

    uint256 constant COLL_PRICE = 3000e8; // $3000 (8 dec)
    uint256 constant DEBT_PRICE = 1e8;    // $1 (8 dec)
    uint256 constant POOL_LIQUIDITY = 1_000_000e18;

    function setUp() public {
        lending = new LendingPool(admin);
        collToken = new MockToken("CollToken", "COLL");
        debtToken = new MockToken("DebtToken", "DEBT");

        // forge-lint: disable-next-line(unsafe-typecast)
        collFeed = new MockAggregatorV3(8, int256(COLL_PRICE));
        // forge-lint: disable-next-line(unsafe-typecast)
        debtFeed = new MockAggregatorV3(8, int256(DEBT_PRICE));
        collOracle = new PriceOracle(address(collFeed), 3600);
        debtOracle = new PriceOracle(address(debtFeed), 3600);

        vm.startPrank(admin);
        lending.configureAsset(
            address(collToken), address(collOracle),
            0.75e18, 0.80e18, 0.05e18, true, false
        );
        lending.configureAsset(
            address(debtToken), address(debtOracle),
            0.75e18, 0.80e18, 0.05e18, false, true
        );
        vm.stopPrank();

        // Seed the lending pool with borrowable liquidity via depositLiquidity
        debtToken.mint(lender, POOL_LIQUIDITY);
        vm.startPrank(lender);
        debtToken.approve(address(lending), type(uint256).max);
        lending.depositLiquidity(address(debtToken), POOL_LIQUIDITY);
        vm.stopPrank();
    }

    // ── Deposit collateral ────────────────────────────────────────────────────
    function test_deposit() public {
        collToken.mint(alice, 100e18);
        vm.startPrank(alice);
        collToken.approve(address(lending), type(uint256).max);
        lending.deposit(address(collToken), 100e18);
        vm.stopPrank();
        assertEq(lending.totalDeposited(address(collToken)), 100e18);
    }

    function test_deposit_revert_zeroAmount() public {
        vm.expectRevert(LendingPool.ZeroAmount.selector);
        lending.deposit(address(collToken), 0);
    }

    function test_deposit_revert_notCollateral() public {
        debtToken.mint(alice, 1e18);
        vm.startPrank(alice);
        debtToken.approve(address(lending), type(uint256).max);
        vm.expectRevert(LendingPool.NotCollateral.selector);
        lending.deposit(address(debtToken), 1e18);
        vm.stopPrank();
    }

    // ── depositLiquidity ──────────────────────────────────────────────────────
    function test_depositLiquidity_succeeds() public view {
        assertEq(lending.totalDeposited(address(debtToken)), POOL_LIQUIDITY);
    }

    function test_depositLiquidity_revert_notBorrowable() public {
        collToken.mint(lender, 1e18);
        vm.startPrank(lender);
        collToken.approve(address(lending), type(uint256).max);
        vm.expectRevert(LendingPool.NotBorrowable.selector);
        lending.depositLiquidity(address(collToken), 1e18);
        vm.stopPrank();
    }

    // ── Borrow ────────────────────────────────────────────────────────────────
    function test_borrow_succeeds() public {
        collToken.mint(alice, 1e18);
        vm.startPrank(alice);
        collToken.approve(address(lending), type(uint256).max);
        debtToken.approve(address(lending), type(uint256).max);
        // 1 COLL = $3000, LTV 75% → max borrow $2250; ask for 2000
        lending.borrow(address(collToken), 1e18, address(debtToken), 2000e18);
        vm.stopPrank();
        assertGt(debtToken.balanceOf(alice), 0);
    }

    function test_borrow_revert_exceedsLTV() public {
        collToken.mint(alice, 1e18);
        vm.startPrank(alice);
        collToken.approve(address(lending), type(uint256).max);
        vm.expectRevert(LendingPool.BorrowExceedsLTV.selector);
        // 1 COLL = $3000 → max borrow = 2250 DEBT; asking for 2500
        lending.borrow(address(collToken), 1e18, address(debtToken), 2500e18);
        vm.stopPrank();
    }

    function test_borrow_revert_zeroAmount() public {
        vm.expectRevert(LendingPool.ZeroAmount.selector);
        lending.borrow(address(collToken), 1e18, address(debtToken), 0);
    }

    // ── Repay ─────────────────────────────────────────────────────────────────
    function test_repay_full() public {
        collToken.mint(alice, 1e18);
        vm.startPrank(alice);
        collToken.approve(address(lending), type(uint256).max);
        debtToken.approve(address(lending), type(uint256).max);
        lending.borrow(address(collToken), 1e18, address(debtToken), 2000e18);

        // Mint extra for potential interest accrual
        debtToken.mint(alice, 100e18);
        lending.repay(address(collToken), address(debtToken), 2100e18);
        vm.stopPrank();
    }

    // ── Liquidation ───────────────────────────────────────────────────────────
    function test_liquidate_succeeds() public {
        collToken.mint(alice, 1e18);
        vm.startPrank(alice);
        collToken.approve(address(lending), type(uint256).max);
        debtToken.approve(address(lending), type(uint256).max);
        lending.borrow(address(collToken), 1e18, address(debtToken), 2000e18);
        vm.stopPrank();

        // Drop collateral price: $2400 → threshold = $1920 < $2000 → unhealthy
        collFeed.setAnswer(2400e8);

        debtToken.mint(liquidator, 5000e18);
        vm.startPrank(liquidator);
        debtToken.approve(address(lending), type(uint256).max);
        lending.liquidate(address(collToken), address(debtToken), alice, 1000e18);
        vm.stopPrank();
        // Liquidator received collateral
        assertGt(collToken.balanceOf(liquidator), 0);
    }

    function test_liquidate_revert_healthOK() public {
        collToken.mint(alice, 1e18);
        vm.startPrank(alice);
        collToken.approve(address(lending), type(uint256).max);
        debtToken.approve(address(lending), type(uint256).max);
        lending.borrow(address(collToken), 1e18, address(debtToken), 1000e18);
        vm.stopPrank();

        debtToken.mint(liquidator, 5000e18);
        vm.startPrank(liquidator);
        debtToken.approve(address(lending), type(uint256).max);
        vm.expectRevert(LendingPool.HealthFactorOK.selector);
        lending.liquidate(address(collToken), address(debtToken), alice, 500e18);
        vm.stopPrank();
    }

    // ── Health factor ──────────────────────────────────────────────────────────
    function test_healthFactor_infinite_noDebt() public view {
        uint256 hf = lending.healthFactor(address(collToken), address(debtToken), alice);
        assertEq(hf, type(uint256).max);
    }

    // ── Interest rate ──────────────────────────────────────────────────────────
    function test_borrowRate_baseRate() public view {
        uint256 rate = lending.borrowRate(address(debtToken));
        assertGe(rate, lending.BASE_RATE());
    }

    // ── PriceOracle ───────────────────────────────────────────────────────────
    function test_oracle_getPrice() public view {
        uint256 price = collOracle.getPrice();
        // $3000 scaled to 18 decimals = 3000e18
        assertEq(price, 3000e18);
    }

    function test_oracle_revert_stale() public {
        vm.warp(block.timestamp + 3601);
        vm.expectRevert();
        collOracle.getPrice();
    }

    function test_oracle_revert_negative() public {
        collFeed.setAnswer(-1);
        vm.expectRevert(PriceOracle.NegativePrice.selector);
        collOracle.getPrice();
    }

    // ── Fuzz: borrow amount stays within LTV ──────────────────────────────────
    function testFuzz_borrow_withinLTV(uint256 borrowAmt) public {
        uint256 collAmount = 1e18;
        uint256 maxBorrow = 2250e18; // $3000 * 75%
        borrowAmt = bound(borrowAmt, 1, maxBorrow);

        collToken.mint(alice, collAmount);
        vm.startPrank(alice);
        collToken.approve(address(lending), type(uint256).max);
        debtToken.approve(address(lending), type(uint256).max);
        // borrow() takes collateral directly — no prior deposit() needed
        lending.borrow(address(collToken), collAmount, address(debtToken), borrowAmt);
        vm.stopPrank();
        assertGt(debtToken.balanceOf(alice), 0);
    }

    // ── Fuzz: health factor drops proportionally as price drops ──────────────
    function testFuzz_healthFactor_drops_on_price_decrease(uint256 newPriceUsd) public {
        // Borrow at 66% LTV: 1 COLL @ $3000, borrow 2000 DEBT @ $1
        collToken.mint(alice, 1e18);
        vm.startPrank(alice);
        collToken.approve(address(lending), type(uint256).max);
        debtToken.approve(address(lending), type(uint256).max);
        lending.borrow(address(collToken), 1e18, address(debtToken), 2000e18);
        vm.stopPrank();

        uint256 hfBefore = lending.healthFactor(address(collToken), address(debtToken), alice);

        // Drop collateral price to somewhere between $100 and $2999
        newPriceUsd = bound(newPriceUsd, 100, 2999);
        collFeed.setAnswer(int256(newPriceUsd) * 1e8);

        uint256 hfAfter = lending.healthFactor(address(collToken), address(debtToken), alice);
        assertLt(hfAfter, hfBefore, "Health factor must decrease when collateral price drops");
    }
}
