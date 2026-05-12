// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface AggregatorV3Interface {
    function latestRoundData()
        external
        view
        returns (uint80, int256 answer, uint256, uint256 updatedAt, uint80);
}

contract OracleAdapter {
    uint256 public constant STALENESS_THRESHOLD = 1 hours;

    AggregatorV3Interface public immutable feed;

    constructor(address feed_) {
        require(feed_ != address(0), "OA: zero feed");
        feed = AggregatorV3Interface(feed_);
    }

    function getPrice() external view returns (int256) {
        (, int256 price, , uint256 updatedAt, ) = feed.latestRoundData();
        _checkFresh(updatedAt, STALENESS_THRESHOLD);
        require(price > 0, "OA: non-positive price");
        return price;
    }

    function assertFresh(uint256 maxAge) external view {
        (, , , uint256 updatedAt, ) = feed.latestRoundData();
        _checkFresh(updatedAt, maxAge);
    }

    function _checkFresh(uint256 updatedAt, uint256 maxAge) internal view {
        require(updatedAt > 0, "OA: round not complete");
        require(block.timestamp - updatedAt <= maxAge, "OA: stale price");
    }
}
