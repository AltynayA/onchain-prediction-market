// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

//test-only Chainlink aggregator mock. not for mainnet deployment.
contract MockAggregator {
    int256 public price;
    uint256 public updatedAt;
    uint80 public roundId;
    uint8 public decimals_;

    constructor(int256 initialPrice_, uint8 decimals__) {
        price = initialPrice_;
        updatedAt = block.timestamp;
        roundId = 1;
        decimals_ = decimals__;
    }

    function decimals() external view returns (uint8) {
        return decimals_;
    }

    function latestRoundData()
        external
        view
        returns (uint80, int256, uint256, uint256, uint80)
    {
        return (roundId, price, updatedAt, updatedAt, roundId);
    }

    //test helpers
    function setPrice(int256 p) external {
        price = p;
        updatedAt = block.timestamp;
        roundId++;
    }
    function setStale(uint256 ageSeconds) external {
        updatedAt = block.timestamp - ageSeconds;
    }
    function setZeroPrice() external {
        price = 0;
    }
    function refresh() external {
        updatedAt = block.timestamp;
    }
}
