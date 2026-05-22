// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/core/AMMPool.sol";
import "../src/core/YieldVault.sol";
import "../src/tokens/GovToken.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockERC20Mintable is ERC20 {
    constructor(string memory n, string memory s) ERC20(n, s) {}
    function mint(address to, uint256 amount) external { _mint(to, amount); }
}

contract AMMHandler is Test {
    AMMPool public pool;
    MockERC20Mintable public token0;
    MockERC20Mintable public token1;
    address internal actor = makeAddr("actor");

    uint256 public ghost_totalIn0;
    uint256 public ghost_totalIn1;

    constructor() {
        token0 = new MockERC20Mintable("T0", "T0");
        token1 = new MockERC20Mintable("T1", "T1");
        if (address(token0) > address(token1)) {
            (token0, token1) = (token1, token0);
        }
        pool = new AMMPool(address(token0), address(token1));

        token0.mint(actor, 1_000_000e18);
        token1.mint(actor, 1_000_000e18);
        vm.prank(actor);
        token0.approve(address(pool), type(uint256).max);
        vm.prank(actor);
        token1.approve(address(pool), type(uint256).max);

        vm.prank(actor);
        pool.addLiquidity(100_000e18, 100_000e18, 0, 0, actor);
        ghost_totalIn0 = 100_000e18;
        ghost_totalIn1 = 100_000e18;
    }

    function swap(uint256 amountIn, bool zeroForOne) public {
        amountIn = bound(amountIn, 1e15, 10_000e18);
        if (zeroForOne) {
            token0.mint(actor, amountIn);
            vm.prank(actor);
            pool.swapExactIn(true, amountIn, 0, actor);
            ghost_totalIn0 += amountIn;
        } else {
            token1.mint(actor, amountIn);
            vm.prank(actor);
            pool.swapExactIn(false, amountIn, 0, actor);
            ghost_totalIn1 += amountIn;
        }
    }

    function addLiquidity(uint256 amount) public {
        amount = bound(amount, 1e18, 50_000e18);
        token0.mint(actor, amount);
        token1.mint(actor, amount);
        vm.prank(actor);
        pool.addLiquidity(amount, amount, 0, 0, actor);
    }
}

contract GovTokenHandler is Test {
    GovTokenV1 public token;
    address internal admin = makeAddr("admin");
    address public minter = makeAddr("minter");

    uint256 public ghost_minted;
    uint256 public ghost_burned;

    constructor() {
        GovTokenV1 impl = new GovTokenV1();
        bytes memory initData = abi.encodeCall(GovTokenV1.initialize, (admin, minter));
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), initData);
        token = GovTokenV1(address(proxy));
    }

    function mint(address to, uint256 amount) public {
        to = address(uint160(bound(uint256(uint160(to)), 1, type(uint160).max)));
        amount = bound(amount, 1, 1_000_000e18);
        if (token.totalSupply() + amount > token.MAX_SUPPLY()) return;
        vm.prank(minter);
        token.mint(to, amount);
        ghost_minted += amount;
    }

    function burn(uint256 amount) public {
        uint256 bal = token.balanceOf(minter);
        if (bal == 0) return;
        amount = bound(amount, 1, bal);
        vm.prank(minter);
        token.burn(amount);
        ghost_burned += amount;
    }
}

contract VaultHandler is Test {
    YieldVaultV1 public vault;
    MockERC20Mintable public asset;
    address internal actor = makeAddr("vaultActor");

    uint256 public ghost_totalDeposited;
    uint256 public ghost_totalWithdrawn;

    constructor() {
        asset = new MockERC20Mintable("MockAsset", "mA");
        YieldVaultV1 impl = new YieldVaultV1();
        bytes memory initData = abi.encodeCall(
            YieldVaultV1.initialize,
            (address(asset), "Vault", "vTKN", address(this))
        );
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), initData);
        vault = YieldVaultV1(address(proxy));

        asset.mint(actor, 10_000_000e18);
        vm.prank(actor);
        asset.approve(address(vault), type(uint256).max);
    }

    function deposit(uint256 assets) public {
        assets = bound(assets, 1e6, 100_000e18);
        asset.mint(actor, assets);
        vm.prank(actor);
        vault.deposit(assets, actor);
        ghost_totalDeposited += assets;
    }

    function redeem(uint256 shares) public {
        uint256 bal = vault.balanceOf(actor);
        if (bal == 0) return;
        shares = bound(shares, 1, bal);
        vm.prank(actor);
        uint256 assetsOut = vault.redeem(shares, actor, actor);
        ghost_totalWithdrawn += assetsOut;
    }
}

contract AMMInvariantTest is Test {
    AMMHandler internal handler;

    function setUp() public {
        handler = new AMMHandler();
        targetContract(address(handler));
    }

    function invariant_k_never_decreases() public view {
        (uint256 r0, uint256 r1) = handler.pool().getReserves();
        uint256 k0 = 100_000e18 * 100_000e18;
        assertGe(r0 * r1, k0);
    }

    function invariant_lpSupply_positive() public view {
        uint256 ts = handler.pool().totalSupply();
        (uint256 r0, uint256 r1) = handler.pool().getReserves();
        if (r0 > 0 && r1 > 0) {
            assertGt(ts, 0);
        }
    }

    function invariant_reserves_match_balances() public view {
        (uint256 r0, uint256 r1) = handler.pool().getReserves();
        uint256 bal0 = handler.token0().balanceOf(address(handler.pool()));
        uint256 bal1 = handler.token1().balanceOf(address(handler.pool()));
        assertEq(r0, bal0);
        assertEq(r1, bal1);
    }
}

contract GovTokenInvariantTest is Test {
    GovTokenHandler internal handler;

    function setUp() public {
        handler = new GovTokenHandler();
        targetContract(address(handler));
    }

    function invariant_totalSupply_conservation() public view {
        assertEq(
            handler.token().totalSupply(),
            handler.ghost_minted() - handler.ghost_burned()
        );
    }

    function invariant_maxSupply_never_exceeded() public view {
        assertLe(handler.token().totalSupply(), handler.token().MAX_SUPPLY());
    }

    function invariant_balance_le_totalSupply() public view {
        address minter = handler.minter();
        assertLe(handler.token().balanceOf(minter), handler.token().totalSupply());
    }
}

contract VaultInvariantTest is Test {
    VaultHandler internal handler;

    function setUp() public {
        handler = new VaultHandler();
        // Seed the vault via the handler so ghost accounting stays consistent
        // with the invariant `totalAssets >= ghost_deposited - ghost_withdrawn`.
        handler.deposit(1000e18);
        targetContract(address(handler));
    }

    function invariant_convertShares_roundtrip() public view {
        YieldVaultV1 vault = handler.vault();
        uint256 shares = 1e18;
        uint256 assets = vault.convertToAssets(shares);
        uint256 sharesBack = vault.convertToShares(assets);
        assertLe(sharesBack, shares);
    }

    function invariant_convertAssets_roundtrip() public view {
        YieldVaultV1 vault = handler.vault();
        uint256 assets = 1e18;
        uint256 shares = vault.convertToShares(assets);
        uint256 assetsBack = vault.convertToAssets(shares);
        assertLe(assetsBack, assets);
    }

    function invariant_totalAssets_matches_balance() public view {
        YieldVaultV1 vault = handler.vault();
        assertEq(vault.totalAssets(), handler.asset().balanceOf(address(vault)));
    }

    function invariant_totalAssets_ge_net_deposits() public view {
        YieldVaultV1 vault = handler.vault();
        uint256 net = handler.ghost_totalDeposited() - handler.ghost_totalWithdrawn();
        assertGe(vault.totalAssets(), net);
    }
}
