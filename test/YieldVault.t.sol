// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "../src/core/YieldVault.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockAsset is ERC20 {
    constructor() ERC20("MockUSDC", "mUSDC") {}
    function mint(address to, uint256 amount) external { _mint(to, amount); }
}

contract YieldVaultTest is Test {
    YieldVaultV1 internal vault;
    MockAsset internal asset;
    address internal admin = makeAddr("admin");
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");

    function setUp() public {
        asset = new MockAsset();
        YieldVaultV1 impl = new YieldVaultV1();
        bytes memory initData = abi.encodeCall(
            YieldVaultV1.initialize,
            (address(asset), "DeFi Yield Vault", "DYV", admin)
        );
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), initData);
        vault = YieldVaultV1(address(proxy));
    }

    // ── Basic ERC-4626 ────────────────────────────────────────────────────────
    function test_asset() public view {
        assertEq(vault.asset(), address(asset));
    }

    function test_deposit() public {
        asset.mint(alice, 1000e18);
        vm.startPrank(alice);
        asset.approve(address(vault), type(uint256).max);
        uint256 shares = vault.deposit(1000e18, alice);
        vm.stopPrank();
        assertEq(vault.balanceOf(alice), shares);
        assertEq(shares, vault.convertToShares(1000e18));
    }

    function test_withdraw() public {
        asset.mint(alice, 1000e18);
        vm.startPrank(alice);
        asset.approve(address(vault), type(uint256).max);
        vault.deposit(1000e18, alice);
        vault.withdraw(500e18, alice, alice);
        vm.stopPrank();
        assertEq(asset.balanceOf(alice), 500e18);
    }

    function test_redeem() public {
        asset.mint(alice, 1000e18);
        vm.startPrank(alice);
        asset.approve(address(vault), type(uint256).max);
        uint256 shares = vault.deposit(1000e18, alice);
        uint256 assetsOut = vault.redeem(shares, alice, alice);
        vm.stopPrank();
        assertEq(assetsOut, 1000e18);
        assertEq(vault.balanceOf(alice), 0);
    }

    function test_mint_shares() public {
        asset.mint(alice, 2000e18);
        vm.startPrank(alice);
        asset.approve(address(vault), type(uint256).max);
        uint256 assetsNeeded = vault.mint(500e18, alice);
        vm.stopPrank();
        assertEq(vault.balanceOf(alice), 500e18);
        assertGe(assetsNeeded, 500e18);
    }

    // ── Yield injection (share price increase) ────────────────────────────────
    function test_yieldInjection_increaseSharePrice() public {
        asset.mint(alice, 1000e18);
        vm.startPrank(alice);
        asset.approve(address(vault), type(uint256).max);
        vault.deposit(1000e18, alice);
        vm.stopPrank();

        uint256 sharesBefore = vault.balanceOf(alice);
        uint256 assetsBefore = vault.convertToAssets(sharesBefore);

        // Inject 100e18 yield
        asset.mint(admin, 100e18);
        vm.startPrank(admin);
        asset.approve(address(vault), type(uint256).max);
        vault.injectYield(100e18);
        vm.stopPrank();

        uint256 assetsAfter = vault.convertToAssets(sharesBefore);
        assertGt(assetsAfter, assetsBefore);
    }

    // ── Pause ──────────────────────────────────────────────────────────────────
    function test_pause_preventsDeposit() public {
        vm.prank(admin);
        vault.pause();
        asset.mint(alice, 100e18);
        vm.startPrank(alice);
        asset.approve(address(vault), type(uint256).max);
        vm.expectRevert();
        vault.deposit(100e18, alice);
        vm.stopPrank();
    }

    function test_unpause_allowsDeposit() public {
        vm.prank(admin);
        vault.pause();
        vm.prank(admin);
        vault.unpause();
        asset.mint(alice, 100e18);
        vm.startPrank(alice);
        asset.approve(address(vault), type(uint256).max);
        uint256 shares = vault.deposit(100e18, alice);
        vm.stopPrank();
        assertGt(shares, 0);
    }

    // ── Max deposit cap ────────────────────────────────────────────────────────
    function test_deposit_revert_tooLarge() public {
        uint256 tooLarge = vault.MAX_DEPOSIT_PER_TX() + 1;
        asset.mint(alice, tooLarge);
        vm.startPrank(alice);
        asset.approve(address(vault), type(uint256).max);
        vm.expectRevert("YieldVault: deposit too large");
        vault.deposit(tooLarge, alice);
        vm.stopPrank();
    }

    // ── UUPS upgrade V1→V2 ────────────────────────────────────────────────────
    function test_upgradeToV2() public {
        YieldVaultV2 implV2 = new YieldVaultV2();
        vm.prank(admin);
        vault.upgradeToAndCall(address(implV2), "");
        YieldVaultV2 v2 = YieldVaultV2(address(vault));
        assertEq(v2.version(), "2.0.0");
        assertEq(v2.VERSION(), 2);
    }

    function test_upgrade_revert_notUpgrader() public {
        YieldVaultV2 implV2 = new YieldVaultV2();
        vm.expectRevert();
        vm.prank(alice);
        vault.upgradeToAndCall(address(implV2), "");
    }

    // ── V2: performance-fee on yield injection ────────────────────────────────
    function _upgradeToV2() internal returns (YieldVaultV2 v2) {
        YieldVaultV2 implV2 = new YieldVaultV2();
        vm.prank(admin);
        vault.upgradeToAndCall(address(implV2), "");
        v2 = YieldVaultV2(address(vault));
    }

    function test_v2_setPerformanceFee() public {
        YieldVaultV2 v2 = _upgradeToV2();
        address feeRecipient = makeAddr("feeRecipient");

        vm.prank(admin);
        v2.setPerformanceFee(500, feeRecipient); // 5%

        assertEq(v2.performanceFee(), 500);
        assertEq(v2.feeRecipient(), feeRecipient);
    }

    function test_v2_setPerformanceFee_revert_capExceeded() public {
        YieldVaultV2 v2 = _upgradeToV2();
        vm.expectRevert("YieldVaultV2: fee > 30%");
        vm.prank(admin);
        v2.setPerformanceFee(3001, address(this));
    }

    function test_v2_setPerformanceFee_revert_notAdmin() public {
        YieldVaultV2 v2 = _upgradeToV2();
        vm.expectRevert();
        vm.prank(alice);
        v2.setPerformanceFee(500, alice);
    }

    function test_v2_injectYieldWithFee_routesFee() public {
        YieldVaultV2 v2 = _upgradeToV2();
        address feeRecipient = makeAddr("feeRecipient");

        vm.prank(admin);
        v2.setPerformanceFee(500, feeRecipient); // 5%

        // Seed a depositor so totalAssets > 0
        asset.mint(alice, 1000e18);
        vm.startPrank(alice);
        asset.approve(address(vault), type(uint256).max);
        vault.deposit(1000e18, alice);
        vm.stopPrank();

        // Inject 200e18: 5% (10e18) goes to feeRecipient, 190e18 enters the vault
        asset.mint(admin, 200e18);
        vm.startPrank(admin);
        asset.approve(address(vault), type(uint256).max);
        uint256 vaultBefore = asset.balanceOf(address(vault));
        v2.injectYieldWithFee(200e18);
        vm.stopPrank();

        assertEq(asset.balanceOf(feeRecipient), 10e18);
        assertEq(asset.balanceOf(address(vault)), vaultBefore + 190e18);
    }

    function test_v2_injectYieldWithFee_noRecipient_skipsFee() public {
        YieldVaultV2 v2 = _upgradeToV2();
        // Fee bps set but recipient is address(0) → the `if (fee > 0 && feeRecipient != 0)`
        // branch is skipped; only `net` (amount - fee) is transferred to the vault.
        // The fee component stays in the caller's wallet (covers the false-branch of the if).
        vm.prank(admin);
        v2.setPerformanceFee(500, address(0));

        asset.mint(alice, 1000e18);
        vm.startPrank(alice);
        asset.approve(address(vault), type(uint256).max);
        vault.deposit(1000e18, alice);
        vm.stopPrank();

        asset.mint(admin, 200e18);
        vm.startPrank(admin);
        asset.approve(address(vault), type(uint256).max);
        uint256 vaultBefore   = asset.balanceOf(address(vault));
        uint256 adminBefore   = asset.balanceOf(admin);
        v2.injectYieldWithFee(200e18);
        vm.stopPrank();

        // net = 200 - (200 * 500 / 10000) = 200 - 10 = 190 enters the vault
        assertEq(asset.balanceOf(address(vault)), vaultBefore + 190e18);
        // the 10e18 fee component stays in admin's wallet (skipped branch)
        assertEq(asset.balanceOf(admin), adminBefore - 190e18);
    }

    function test_v2_injectYieldWithFee_zeroFee_routesAllToVault() public {
        YieldVaultV2 v2 = _upgradeToV2();
        // performanceFee = 0 → fee = 0, the inner `if (fee > 0 && ...)` is false,
        // and the full amount enters the vault.
        vm.prank(admin);
        v2.setPerformanceFee(0, makeAddr("ignored"));

        asset.mint(alice, 1000e18);
        vm.startPrank(alice);
        asset.approve(address(vault), type(uint256).max);
        vault.deposit(1000e18, alice);
        vm.stopPrank();

        asset.mint(admin, 100e18);
        vm.startPrank(admin);
        asset.approve(address(vault), type(uint256).max);
        uint256 vaultBefore = asset.balanceOf(address(vault));
        v2.injectYieldWithFee(100e18);
        vm.stopPrank();

        assertEq(asset.balanceOf(address(vault)), vaultBefore + 100e18);
    }

    // ── Pause guard on every ERC-4626 entry point ─────────────────────────────
    function test_pause_preventsMint() public {
        asset.mint(alice, 1000e18);
        vm.prank(alice);
        asset.approve(address(vault), type(uint256).max);

        vm.prank(admin);
        vault.pause();

        vm.expectRevert();
        vm.prank(alice);
        vault.mint(100e18, alice);
    }

    function test_pause_preventsWithdraw() public {
        asset.mint(alice, 1000e18);
        vm.startPrank(alice);
        asset.approve(address(vault), type(uint256).max);
        vault.deposit(1000e18, alice);
        vm.stopPrank();

        vm.prank(admin);
        vault.pause();

        vm.expectRevert();
        vm.prank(alice);
        vault.withdraw(100e18, alice, alice);
    }

    function test_pause_preventsRedeem() public {
        asset.mint(alice, 1000e18);
        vm.startPrank(alice);
        asset.approve(address(vault), type(uint256).max);
        uint256 shares = vault.deposit(1000e18, alice);
        vm.stopPrank();

        vm.prank(admin);
        vault.pause();

        vm.expectRevert();
        vm.prank(alice);
        vault.redeem(shares, alice, alice);
    }

    // ── Access control on admin-only setters ─────────────────────────────────
    function test_pause_revert_notPauser() public {
        vm.expectRevert();
        vm.prank(alice);
        vault.pause();
    }

    function test_injectYield_revert_notYieldManager() public {
        asset.mint(alice, 100e18);
        vm.prank(alice);
        asset.approve(address(vault), type(uint256).max);

        vm.expectRevert();
        vm.prank(alice);
        vault.injectYield(100e18);
    }

    // ── decimals() matches underlying asset ───────────────────────────────────
    function test_decimals_matchesAsset() public view {
        assertEq(vault.decimals(), asset.decimals());
    }

    // ── Fuzz: deposit → redeem roundtrip ─────────────────────────────────────
    function testFuzz_depositRedeem(uint256 amount) public {
        amount = bound(amount, 1e6, vault.MAX_DEPOSIT_PER_TX());
        asset.mint(alice, amount);
        vm.startPrank(alice);
        asset.approve(address(vault), type(uint256).max);
        uint256 shares = vault.deposit(amount, alice);
        uint256 assetsOut = vault.redeem(shares, alice, alice);
        vm.stopPrank();
        // Should get back at most what was deposited (rounding down)
        assertLe(assetsOut, amount);
        assertGe(assetsOut, amount - 1); // at most 1 wei rounding loss
    }

    // ── Fuzz: share price monotonically increases with yield ──────────────────
    function testFuzz_yieldIncreasesSharePrice(uint256 yieldAmount) public {
        yieldAmount = bound(yieldAmount, 1e6, 1_000_000e18);
        asset.mint(alice, 1000e18);
        vm.startPrank(alice);
        asset.approve(address(vault), type(uint256).max);
        vault.deposit(1000e18, alice);
        vm.stopPrank();

        uint256 priceBeforeWad = vault.convertToAssets(1e18);

        asset.mint(admin, yieldAmount);
        vm.startPrank(admin);
        asset.approve(address(vault), type(uint256).max);
        vault.injectYield(yieldAmount);
        vm.stopPrank();

        uint256 priceAfterWad = vault.convertToAssets(1e18);
        assertGe(priceAfterWad, priceBeforeWad);
    }
}
