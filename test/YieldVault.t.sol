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
