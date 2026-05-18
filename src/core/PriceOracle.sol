// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @dev Minimal Chainlink AggregatorV3 interface
interface AggregatorV3Interface {
    function decimals() external view returns (uint8);
    function latestRoundData()
        external
        view
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        );
}

/// @title PriceOracle — wraps a Chainlink AggregatorV3 feed with staleness check
contract PriceOracle {
    AggregatorV3Interface public immutable feed;
    uint256 public immutable stalenessThreshold; // seconds

    error StalePrice(uint256 updatedAt, uint256 threshold);
    error NegativePrice();
    error RoundNotComplete();

    constructor(address _feed, uint256 _stalenessThreshold) {
        require(_feed != address(0), "PriceOracle: zero feed");
        require(_stalenessThreshold > 0, "PriceOracle: zero threshold");
        feed = AggregatorV3Interface(_feed);
        stalenessThreshold = _stalenessThreshold;
    }

    /// @notice Returns the latest price scaled to 18 decimals, reverts if stale
    function getPrice() external view returns (uint256 price) {
        // slither-disable-next-line unused-return
        (uint80 roundId, int256 answer, , uint256 updatedAt, uint80 answeredInRound) =
            feed.latestRoundData();

        if (answeredInRound < roundId) revert RoundNotComplete();
        if (answer <= 0) revert NegativePrice();
        // solhint-disable-next-line not-rely-on-time
        if (block.timestamp - updatedAt > stalenessThreshold) {
            revert StalePrice(updatedAt, stalenessThreshold);
        }

        uint8 dec = feed.decimals();
        price = uint256(answer);
        if (dec < 18) {
            price = price * 10 ** (18 - dec);
        } else if (dec > 18) {
            price = price / 10 ** (dec - 18);
        }
    }

    /// @notice Raw latestRoundData passthrough (no staleness check)
    function getRawData()
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        // slither-disable-next-line unused-return
        (roundId, answer, startedAt, updatedAt, answeredInRound) = feed.latestRoundData();
    }
}
