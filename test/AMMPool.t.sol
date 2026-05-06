// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/core/AMMPool.sol";
import "../src/core/PoolFactory.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockERC20 is ERC20 {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {}
    function mint(address to, uint256 amount) external { _mint(to, amount); }
}

contract AMMPoolTest is Test {
    AMMPool internal pool;
    MockERC20 internal tokenA;
    MockERC20 internal tokenB;
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");

    uint256 constant INIT_LIQUIDITY = 100_000e18;

    function setUp() public {
        tokenA = new MockERC20("TokenA", "TKA");
        tokenB = new MockERC20("TokenB", "TKB");

        // Sort tokens as pool does
        (address t0, address t1) = address(tokenA) < address(tokenB)
            ? (address(tokenA), address(tokenB))
            : (address(tokenB), address(tokenA));

        pool = new AMMPool(t0, t1);

        // Mint and add initial liquidity
        tokenA.mint(alice, INIT_LIQUIDITY * 2);
        tokenB.mint(alice, INIT_LIQUIDITY * 2);
        vm.startPrank(alice);
        tokenA.approve(address(pool), type(uint256).max);
        tokenB.approve(address(pool), type(uint256).max);
        pool.addLiquidity(INIT_LIQUIDITY, INIT_LIQUIDITY, 0, 0, alice);
        vm.stopPrank();
    }

    // ── LP token mechanics ─────────────────────────────────────────────────────
    function test_addLiquidity_initialMint() public view {
        // minimum liquidity locked = 1000
        assertGt(pool.totalSupply(), 0);
        assertGt(pool.balanceOf(alice), 0);
    }

    function test_addLiquidity_proportional() public {
        tokenA.mint(bob, 10_000e18);
        tokenB.mint(bob, 10_000e18);
        vm.startPrank(bob);
        tokenA.approve(address(pool), type(uint256).max);
        tokenB.approve(address(pool), type(uint256).max);
        uint256 lpBefore = pool.totalSupply();
        (, , uint256 lp) = pool.addLiquidity(10_000e18, 10_000e18, 0, 0, bob);
        vm.stopPrank();
        assertGt(pool.totalSupply(), lpBefore);
        assertEq(pool.balanceOf(bob), lp);
    }

    function test_removeLiquidity() public {
        uint256 lpBalance = pool.balanceOf(alice);
        uint256 halfLp = lpBalance / 2;
        vm.prank(alice);
        (uint256 a0, uint256 a1) = pool.removeLiquidity(halfLp, 0, 0, alice);
        assertGt(a0, 0);
        assertGt(a1, 0);
        assertEq(pool.balanceOf(alice), lpBalance - halfLp);
    }

    function test_removeLiquidity_revert_zero() public {
        vm.expectRevert(AMMPool.InsufficientLiquidityBurned.selector);
        vm.prank(alice);
        pool.removeLiquidity(0, 0, 0, alice);
    }

    // ── Swaps ─────────────────────────────────────────────────────────────────
    function test_swapExactIn_zeroForOne() public {
        tokenA.mint(bob, 1_000e18);
        vm.startPrank(bob);
        tokenA.approve(address(pool), type(uint256).max);
        bool zeroForOne = address(pool.token0()) == address(tokenA);
        uint256 out = pool.swapExactIn(zeroForOne, 1_000e18, 0, bob);
        vm.stopPrank();
        assertGt(out, 0);
    }

    function test_swapExactIn_revert_slippage() public {
        tokenA.mint(bob, 1_000e18);
        vm.startPrank(bob);
        tokenA.approve(address(pool), type(uint256).max);
        bool zeroForOne = address(pool.token0()) == address(tokenA);
        vm.expectRevert(AMMPool.SlippageExceeded.selector);
        pool.swapExactIn(zeroForOne, 1_000e18, type(uint256).max, bob);
        vm.stopPrank();
    }

    function test_swapExactIn_revert_zeroInput() public {
        vm.expectRevert(AMMPool.InsufficientInputAmount.selector);
        pool.swapExactIn(true, 0, 0, bob);
    }

    function test_fee_captured() public {
        (uint256 r0before, uint256 r1before) = pool.getReserves();
        tokenA.mint(bob, 1_000e18);
        vm.startPrank(bob);
        tokenA.approve(address(pool), type(uint256).max);
        bool zeroForOne = address(pool.token0()) == address(tokenA);
        uint256 out = pool.swapExactIn(zeroForOne, 1_000e18, 0, bob);
        vm.stopPrank();
        (uint256 r0after, uint256 r1after) = pool.getReserves();
        // k must be >= before swap (fees increase k slightly)
        assertGe(r0after * r1after, r0before * r1before);
        assertTrue(out > 0);
    }

    // ── Factory ───────────────────────────────────────────────────────────────
    function test_factory_CREATE() public {
        PoolFactory factory = new PoolFactory();
        MockERC20 t0 = new MockERC20("T0", "T0");
        MockERC20 t1 = new MockERC20("T1", "T1");
        address p = factory.createPool(address(t0), address(t1));
        assertFalse(p == address(0));
        assertEq(factory.allPoolsLength(), 1);
    }

    function test_factory_CREATE2() public {
        PoolFactory factory = new PoolFactory();
        MockERC20 t0 = new MockERC20("T0", "T0");
        MockERC20 t1 = new MockERC20("T1", "T1");
        bytes32 salt = keccak256("mysalt");
        address predicted = factory.predictPool(address(t0), address(t1), salt);
        address actual = factory.createPool2(address(t0), address(t1), salt);
        assertEq(predicted, actual);
    }

    function test_factory_revert_poolExists() public {
        PoolFactory factory = new PoolFactory();
        MockERC20 t0 = new MockERC20("T0", "T0");
        MockERC20 t1 = new MockERC20("T1", "T1");
        factory.createPool(address(t0), address(t1));
        vm.expectRevert(PoolFactory.PoolExists.selector);
        factory.createPool(address(t0), address(t1));
    }

    function test_factory_revert_identicalTokens() public {
        PoolFactory factory = new PoolFactory();
        MockERC20 t0 = new MockERC20("T0", "T0");
        vm.expectRevert(PoolFactory.IdenticalTokens.selector);
        factory.createPool(address(t0), address(t0));
    }

    // ── getAmountOut / getAmountIn consistency ────────────────────────────────
    function test_getAmountOut_nonzero() public view {
        uint256 out = pool.getAmountOut(1_000e18, true);
        assertGt(out, 0);
    }

    function test_getAmountIn_nonzero() public view {
        uint256 inAmt = pool.getAmountIn(100e18, true);
        assertGt(inAmt, 0);
    }

    // ── Fuzz: swap preserves k ─────────────────────────────────────────────────
    function testFuzz_swapExactIn_kInvariant(uint256 amountIn) public {
        amountIn = bound(amountIn, 1e15, 10_000e18);
        (uint256 r0before, uint256 r1before) = pool.getReserves();
        tokenA.mint(bob, amountIn);
        vm.startPrank(bob);
        tokenA.approve(address(pool), type(uint256).max);
        bool zeroForOne = address(pool.token0()) == address(tokenA);
        pool.swapExactIn(zeroForOne, amountIn, 0, bob);
        vm.stopPrank();
        (uint256 r0after, uint256 r1after) = pool.getReserves();
        assertGe(r0after * r1after, r0before * r1before);
    }

    // ── Fuzz: add/remove liquidity roundtrip ──────────────────────────────────
    function testFuzz_addRemoveLiquidity(uint256 amount) public {
        amount = bound(amount, 1e18, 50_000e18);
        tokenA.mint(bob, amount);
        tokenB.mint(bob, amount);
        vm.startPrank(bob);
        tokenA.approve(address(pool), type(uint256).max);
        tokenB.approve(address(pool), type(uint256).max);
        (, , uint256 lp) = pool.addLiquidity(amount, amount, 0, 0, bob);
        assertGt(lp, 0);
        (uint256 got0, uint256 got1) = pool.removeLiquidity(lp, 0, 0, bob);
        vm.stopPrank();
        // Should get back close to what was put in (minus rounding)
        assertGt(got0, 0);
        assertGt(got1, 0);
    }
}
