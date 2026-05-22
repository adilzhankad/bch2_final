// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/core/PriceOracle.sol";
import "../src/core/MockAggregatorV3.sol";

/// @dev Mock that returns `answeredInRound < roundId` to exercise the
///      stale-round branch of PriceOracle.getPrice().
contract IncompleteRoundFeed {
    uint8 public constant decimals = 8;

    function latestRoundData()
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        return (5, 100e8, block.timestamp, block.timestamp, 4); // answeredInRound < roundId
    }
}

contract PriceOracleTest is Test {
    MockAggregatorV3 internal feed;
    PriceOracle internal oracle;

    function setUp() public {
        feed = new MockAggregatorV3(8, 2_000e8);
        oracle = new PriceOracle(address(feed), 1 hours);
    }

    // ─── Constructor reverts ──────────────────────────────────────────────────
    function test_constructor_revert_zeroFeed() public {
        vm.expectRevert("PriceOracle: zero feed");
        new PriceOracle(address(0), 1 hours);
    }

    function test_constructor_revert_zeroThreshold() public {
        vm.expectRevert("PriceOracle: zero threshold");
        new PriceOracle(address(feed), 0);
    }

    // ─── Happy path: 8-decimal feed normalised to 18 ─────────────────────────
    function test_getPrice_normalises_8decimals_to_18() public view {
        // 2000 * 1e8 → 2000 * 1e18
        assertEq(oracle.getPrice(), 2_000e18);
    }

    // ─── Happy path: 18-decimal feed passes through unchanged ─────────────────
    function test_getPrice_18decimals_passthrough() public {
        MockAggregatorV3 feed18 = new MockAggregatorV3(18, 5e18);
        PriceOracle oracle18 = new PriceOracle(address(feed18), 1 hours);
        assertEq(oracle18.getPrice(), 5e18);
    }

    // ─── Happy path: feed with > 18 decimals gets scaled down ────────────────
    function test_getPrice_scalesDown_when_decimals_above_18() public {
        // 20-decimal feed: price 5 * 1e20 → 5 * 1e18
        MockAggregatorV3 feed20 = new MockAggregatorV3(20, 5e20);
        PriceOracle oracle20 = new PriceOracle(address(feed20), 1 hours);
        assertEq(oracle20.getPrice(), 5e18);
    }

    // ─── Stale price revert ──────────────────────────────────────────────────
    function test_getPrice_revert_stale() public {
        // Advance time past the staleness window
        vm.warp(block.timestamp + 2 hours);
        vm.expectRevert();
        oracle.getPrice();
    }

    // ─── Negative / zero price reverts ────────────────────────────────────────
    function test_getPrice_revert_zeroAnswer() public {
        feed.setAnswer(0);
        vm.expectRevert(PriceOracle.NegativePrice.selector);
        oracle.getPrice();
    }

    function test_getPrice_revert_negativeAnswer() public {
        feed.setAnswer(-1);
        vm.expectRevert(PriceOracle.NegativePrice.selector);
        oracle.getPrice();
    }

    // ─── answeredInRound < roundId triggers RoundNotComplete ──────────────────
    function test_getPrice_revert_roundIncomplete() public {
        IncompleteRoundFeed badFeed = new IncompleteRoundFeed();
        PriceOracle badOracle = new PriceOracle(address(badFeed), 1 hours);
        vm.expectRevert(PriceOracle.RoundNotComplete.selector);
        badOracle.getPrice();
    }

    // ─── Raw data passthrough returns the same data as the feed ──────────────
    function test_getRawData_passthrough() public view {
        (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound) =
            oracle.getRawData();
        assertEq(roundId, 1);
        assertEq(answer, 2_000e8);
        assertEq(startedAt, updatedAt);
        assertEq(answeredInRound, 1);
    }

    // ─── Immutable getters ────────────────────────────────────────────────────
    function test_immutables_match_constructor_args() public view {
        assertEq(address(oracle.feed()), address(feed));
        assertEq(oracle.stalenessThreshold(), 1 hours);
    }
}
