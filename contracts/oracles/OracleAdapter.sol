// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface AggregatorV3Interface {
    function latestRoundData() external view returns (uint80, int256 answer, uint256, uint256 updatedAt, uint80);
}

contract OracleAdapter {
    uint256 public constant STALENESS_THRESHOLD = 1 hours;

    AggregatorV3Interface public feed;

    constructor(address feed_) {
        feed = AggregatorV3Interface(feed_);
    }

    function getPrice() external view returns (int256) {
        (, int256 price,, uint256 updatedAt,) = feed.latestRoundData();
        require(block.timestamp - updatedAt < STALENESS_THRESHOLD, "Stale price");
        return price;
    }
}
