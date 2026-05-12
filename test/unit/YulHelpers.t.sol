// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {YulHelpers} from "../../contracts/utils/YulHelpers.sol";

contract YulHelpersTest is Test {
    YulHelpers h;

    function setUp() public {
        h = new YulHelpers();
    }

// calcFee 
    function test_calcFee_onePercent() public view {
        assertEq(h.calcFeeYul(1000e6, 100), 10e6);
    }

    function test_calcFee_zeroAmount() public view {
        assertEq(h.calcFeeYul(0, 100), 0);
    }

    function test_calcFee_zeroFeeBps() public view {
        assertEq(h.calcFeeYul(1000e6, 0), 0);
    }

    function test_calcFee_matchesSolidity() public view {
        uint256[4] memory amounts = [uint256(1000e6), 500e18, 1, 999_999e18];
        uint256[4] memory fees = [uint256(100), 30, 50, 9999];
        for (uint i; i < 4; i++) {
            assertEq(
                h.calcFeeYul(amounts[i], fees[i]),
                h.calcFeeSolidity(amounts[i], fees[i]),
                "calcFee mismatch"
            );
        }
    }

// amountOut 
    function test_amountOut_basicCase() public view {
        // amountIn=100, resIn=1000, resOut=1000 → out = 100*1000/1100 = 90
        assertEq(h.amountOutYul(100, 1000, 1000), 90);
    }

    function test_amountOut_matchesSolidity() public view {
        uint256[3] memory ins  = [uint256(100e18), 1, 99_999e18];
        uint256[3] memory resI = [uint256(10_000e18), 1, 50_000e18];
        uint256[3] memory resO = [uint256(10_000e18), 1000e18, 50_000e18];
        for (uint i; i < 3; i++) {
            assertEq(
                h.amountOutYul(ins[i], resI[i], resO[i]),
                h.amountOutSolidity(ins[i], resI[i], resO[i]),
                "amountOut mismatch"
            );
        }
    }

    function test_amountOut_zeroInput_returnsSolidity() public view {
        assertEq(h.amountOutYul(0, 1000, 1000), h.amountOutSolidity(0, 1000, 1000));
    }

// isPowerOfTwo 
    function test_isPowerOfTwo_trueCases() public view {
        uint256[5] memory vals = [uint256(1), 2, 4, 1024, 2**128];
        for (uint i; i < 5; i++) {
            assertTrue(h.isPowerOfTwoYul(vals[i]));
        }
    }

    function test_isPowerOfTwo_falseCases() public view {
        uint256[4] memory vals = [uint256(0), 3, 5, 1023];
        for (uint i; i < 4; i++) {
            assertFalse(h.isPowerOfTwoYul(vals[i]));
        }
    }

    function test_isPowerOfTwo_matchesSolidity() public view {
        uint256[6] memory vals = [uint256(0), 1, 2, 3, 64, 65];
        for (uint i; i < 6; i++) {
            assertEq(
                h.isPowerOfTwoYul(vals[i]),
                h.isPowerOfTwoSolidity(vals[i]),
                "isPowerOfTwo mismatch"
            );
        }
    }
}

contract YulBenchmark is Test {
    YulHelpers h;
    function setUp() public { h = new YulHelpers(); }

    function test_gas_calcFee_yul() public view { h.calcFeeYul(1_000_000e6, 100); }
    function test_gas_calcFee_solidity() public view { h.calcFeeSolidity(1_000_000e6, 100); }

    function test_gas_amountOut_yul() public view { h.amountOutYul(100e18, 10_000e18, 10_000e18); }
    function test_gas_amountOut_solidity() public view { h.amountOutSolidity(100e18, 10_000e18, 10_000e18); }

    function test_gas_isPowerOfTwo_yul() public view { h.isPowerOfTwoYul(1024); }
    function test_gas_isPowerOfTwo_solidity() public view { h.isPowerOfTwoSolidity(1024); }
}
