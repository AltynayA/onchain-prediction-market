// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

// for  prediction market
// each func has a solidity copy  (for gas benchmarking)
contract YulHelpers {

// 1) fee calculation

    // yul ver
    function calcFeeYul(uint256 amount, uint256 feeBps) external pure returns (uint256 fee) {
        assembly {
            // fee = amount * feeBps / 10000
            fee := div(mul(amount, feeBps), 10000)
        }
    }

    // solidity ver
    function calcFeeSolidity(uint256 amount, uint256 feeBps) external pure returns (uint256) {
        return (amount * feeBps) / 10000;
    }

// 2) cpmm amount out 

    // yul ver
    // no overflows
    function amountOutYul(
        uint256 amountIn,
        uint256 reserveIn,
        uint256 reserveOut
    ) external pure returns (uint256 out) {
        assembly {
            // out = amountIn*reserveOut / (reserveIn + amountIn)
            let numerator   := mul(amountIn, reserveOut)
            let denominator := add(reserveIn, amountIn)
            out := div(numerator, denominator)
        }
    }

    // solidity ver
    function amountOutSolidity(
        uint256 amountIn,
        uint256 reserveIn,
        uint256 reserveOut
    ) external pure returns (uint256) {
        if (amountIn == 0 || reserveIn == 0 || reserveOut == 0) return 0;
        return (amountIn * reserveOut) / (reserveIn + amountIn);
    }

// 3) power of two check 

    // yul ver
    function isPowerOfTwoYul(uint256 value) external pure returns (bool result) {
        assembly {
            let isNotZero := gt(value, 0)
            let bitsAnd   := and(value, sub(value, 1))
            let isZero    := iszero(bitsAnd)
            result := and(isNotZero, isZero)
        }
    }

    // solidity ver
    function isPowerOfTwoSolidity(uint256 value) external pure returns (bool) {
        return value > 0 && (value & (value - 1)) == 0;
    }
}
