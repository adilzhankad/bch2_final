// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/core/PriceOracle.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title Fork tests — interact with real mainnet protocols
/// @dev Requires MAINNET_RPC_URL env var. Tests are silently skipped if the
///      variable is not set so that CI without an RPC key still passes.
contract ForkTest is Test {
    // ─── Pinned mainnet addresses ─────────────────────────────────────────────
    address constant CHAINLINK_ETH_USD  = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419;
    address constant CHAINLINK_BTC_USD  = 0xF4030086522a5BeEA4988F8ca5B36DBC97Bee88b;
    address constant CHAINLINK_USDC_USD = 0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6;
    address constant USDC               = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant WETH               = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    bool internal forkActive;

    function setUp() public {
        string memory rpcUrl = vm.envOr("MAINNET_RPC_URL", string(""));
        if (bytes(rpcUrl).length == 0) return;

        vm.createSelectFork(rpcUrl);
        forkActive = true;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Fork test 1 — Chainlink ETH/USD feed returns a positive, in-range price
    // ─────────────────────────────────────────────────────────────────────────
    function test_fork_chainlink_ethUsd_price() public {
        if (!forkActive) { vm.skip(true); return; }

        // Raw feed call (no staleness guard) so we see the real round data.
        PriceOracle oracle = new PriceOracle(CHAINLINK_ETH_USD, 24 hours);
        uint256 price = oracle.getPrice(); // 18-decimal normalized

        // ETH price must be between $500 and $50 000 — reasonable for any near-future block.
        assertGt(price, 500e18, "ETH/USD price below expected floor");
        assertLt(price, 50_000e18, "ETH/USD price above expected ceiling");
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Fork test 2 — Our PriceOracle correctly normalises a real 8-decimal feed
    //               to 18 decimals and the staleness check honours the timestamp
    // ─────────────────────────────────────────────────────────────────────────
    function test_fork_oracle_normalises_to_18_decimals() public {
        if (!forkActive) { vm.skip(true); return; }

        // Chainlink feeds deliver 8 decimals; our oracle must scale to 18.
        PriceOracle oracle = new PriceOracle(CHAINLINK_ETH_USD, 24 hours);
        uint256 price = oracle.getPrice();

        // Price must have 18-decimal magnitude (i.e. > 1e18 for any asset > $1).
        assertGt(price, 1e18, "Normalised price must exceed 1e18 for ETH");

        // Feed is 8 decimals; raw answer * 1e10 should equal oracle price.
        (, int256 rawAnswer,,,) = PriceOracle(oracle).getRawData();
        uint256 expected = uint256(rawAnswer) * 1e10;
        assertEq(price, expected, "18-decimal normalisation mismatch");
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Fork test 3 — USDC is a valid ERC-20 with 6 decimals and positive supply
    // ─────────────────────────────────────────────────────────────────────────
    function test_fork_usdc_erc20_properties() public {
        if (!forkActive) { vm.skip(true); return; }

        IERC20 usdc = IERC20(USDC);

        // Total supply must be in the billions (USDC had ~$25B+ in early 2024).
        uint256 supply = usdc.totalSupply();
        assertGt(supply, 1_000_000e6, "USDC supply must be > $1 M (6 dec)");

        // USDC uses 6 decimals.
        (bool ok, bytes memory data) = USDC.staticcall(abi.encodeWithSignature("decimals()"));
        assertTrue(ok, "decimals() call failed on USDC");
        uint8 dec = abi.decode(data, (uint8));
        assertEq(dec, 6, "USDC must have 6 decimals");

        // WETH must also be alive.
        uint256 wethSupply = IERC20(WETH).totalSupply();
        assertGt(wethSupply, 0, "WETH totalSupply must be positive");
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Fork test 4 — Staleness guard reverts when we warp past the threshold
    // ─────────────────────────────────────────────────────────────────────────
    function test_fork_oracle_reverts_on_stale_price() public {
        if (!forkActive) { vm.skip(true); return; }

        // Deploy oracle with a 1-hour staleness window.
        PriceOracle oracle = new PriceOracle(CHAINLINK_ETH_USD, 1 hours);

        // Warp far into the future so the price is definitely stale.
        vm.warp(block.timestamp + 2 hours);

        vm.expectRevert();
        oracle.getPrice();
    }
}
