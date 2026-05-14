// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {CPMM} from "../../contracts/core/CPMM.sol";
import {PredictionMarket} from "../../contracts/core/PredictionMarket.sol";
import {OutcomeToken} from "../../contracts/tokens/OutcomeToken.sol";
import {CollateralToken} from "../../contracts/tokens/CollateralToken.sol";
import {FeeVault} from "../../contracts/core/FeeVault.sol";
import {MockAggregator} from "../../contracts/mocks/MockAggregator.sol";
import {OracleAdapter} from "../../contracts/oracles/OracleAdapter.sol";
import {YulHelpers} from "../../contracts/utils/YulHelpers.sol";

contract FuzzTest is Test {
    OutcomeToken token;
    CPMM cpmm;
    PredictionMarket market;
    CollateralToken collateral;
    MockAggregator aggregator;
    OracleAdapter oracle;
    FeeVault feeVault;
    YulHelpers yul;

    address admin = makeAddr("admin");
    address resolver = makeAddr("resolver");
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");

    function setUp() public {
        vm.startPrank(admin);

        // Tokens
        token = new OutcomeToken();
        collateral = new CollateralToken("mUSDC", "mUSDC", 6);
        aggregator = new MockAggregator(3000e8, 8);
        oracle = new OracleAdapter(address(aggregator));
        feeVault = new FeeVault(collateral);

        // CPMM
        cpmm = new CPMM(address(token));
        token.grantRole(token.MINTER_ROLE(), admin);
        token.mint(alice, 0, 1_000_000e18);
        token.mint(alice, 1, 1_000_000e18);
        token.mint(bob, 0, 1_000_000e18);
        token.mint(bob, 1, 1_000_000e18);

        // PredictionMarket proxy
        PredictionMarket impl = new PredictionMarket();
        market = PredictionMarket(
            address(
                new ERC1967Proxy(
                    address(impl),
                    abi.encodeCall(
                        PredictionMarket.initialize,
                        (admin, address(collateral), address(token), 1 hours, 2 days, address(feeVault))
                    )
                )
            )
        );
        token.grantRole(token.MINTER_ROLE(), address(market));
        market.grantRole(market.RESOLVER_ROLE(), resolver);

        collateral.mint(alice, 100_000e6);
        collateral.mint(bob, 100_000e6);

        yul = new YulHelpers();
        vm.stopPrank();

        vm.prank(alice);
        token.setApprovalForAll(address(cpmm), true);
        vm.prank(bob);
        token.setApprovalForAll(address(cpmm), true);
        vm.prank(alice);
        collateral.approve(address(market), type(uint256).max);
        vm.prank(bob);
        collateral.approve(address(market), type(uint256).max);

        // Seed pool
        vm.prank(alice);
        cpmm.addLiquidity(100_000e18, 100_000e18, 0);
    }

    // F-01
    function testFuzz_cpmm_kNeverDecreases(uint256 amountIn) public {
        amountIn = bound(amountIn, 1, 10_000e18);
        uint256 kBefore = cpmm.reserveYes() * cpmm.reserveNo();
        vm.prank(bob);
        cpmm.swap(true, amountIn, 0);
        assertGe(cpmm.reserveYes() * cpmm.reserveNo(), kBefore);
    }

    // F-02
    function testFuzz_cpmm_outputLtReserve(uint256 amountIn) public view {
        amountIn = bound(amountIn, 1, 50_000e18);
        assertLt(cpmm.getAmountOut(true, amountIn), cpmm.reserveNo());
    }

    // F-03
    function testFuzz_cpmm_lpRoundtrip(uint256 amount) public {
        amount = bound(amount, 1001, 100_000e18);
        uint256 yesBefore = token.balanceOf(alice, 0);
        vm.prank(alice);
        uint256 lp = cpmm.addLiquidity(amount, amount, 0);
        vm.prank(alice);
        cpmm.removeLiquidity(lp, 0, 0);
        // Should get back close to what was deposited (within 0.01%)
        assertApproxEqRel(token.balanceOf(alice, 0), yesBefore, 0.0001e18);
    }

    // F-04
    function testFuzz_cpmm_previewMatchesSwap(uint256 amountIn) public {
        amountIn = bound(amountIn, 1, 5_000e18);
        uint256 preview = cpmm.getAmountOut(true, amountIn);
        vm.prank(bob);
        uint256 actual = cpmm.swap(true, amountIn, 0);
        assertEq(preview, actual);
    }

    // F-05
    function testFuzz_pm_feeMath(uint256 amount) public {
        amount = bound(amount, 1e4, 10_000e6);
        vm.prank(admin);
        uint256 id = market.createMarket("Q?", block.timestamp + 7 days, address(oracle));

        uint256 vaultBefore = collateral.balanceOf(address(feeVault));
        vm.prank(alice);
        market.buyShares(id, true, amount, 0);

        assertEq(collateral.balanceOf(address(feeVault)) - vaultBefore, (amount * 100) / 10000);
    }

    // F-06: shares minted always < amountIn (compare delta, not absolute balance)
    function testFuzz_pm_sharesLtInput(uint256 amount) public {
        amount = bound(amount, 1e4, 10_000e6);
        vm.prank(admin);
        uint256 id = market.createMarket("Q?", block.timestamp + 7 days, address(oracle));

        uint256 yesBalBefore = token.balanceOf(alice, 0);
        vm.prank(alice);
        market.buyShares(id, true, amount, 0);
        uint256 sharesMinted = token.balanceOf(alice, 0) - yesBalBefore;

        assertLt(sharesMinted, amount);
    }

    // F-07: redeemShares payout never exceeds totalCollateral
    function testFuzz_pm_payoutBounded(uint256 aliceAmt, uint256 bobAmt) public {
        aliceAmt = bound(aliceAmt, 100e6, 5_000e6);
        bobAmt = bound(bobAmt, 100e6, 5_000e6);

        vm.prank(admin);
        uint256 id = market.createMarket("Q?", block.timestamp + 7 days, address(oracle));

        // Snapshot YES balance BEFORE buyShares — setUp minted 1_000_000e18 for CPMM,
        // so token.balanceOf(alice, 0) is huge. We only want the delta from buyShares.
        uint256 yesBefore = token.balanceOf(alice, 0);
        vm.prank(alice);
        market.buyShares(id, true, aliceAmt, 0);
        vm.prank(bob);
        market.buyShares(id, false, bobAmt, 0);

        // Only the shares minted by THIS buyShares call
        uint256 yesShares = token.balanceOf(alice, 0) - yesBefore;

        uint256 totalCol = market.getMarket(id).totalCollateral;

        vm.warp(block.timestamp + 7 days + 1);
        aggregator.refresh();
        vm.prank(resolver);
        market.resolveMarket(id, true);
        vm.warp(block.timestamp + 2 days + 1);
        market.finalizeMarket(id);

        vm.prank(alice);
        token.setApprovalForAll(address(market), true);
        uint256 before = collateral.balanceOf(alice);

        // Redeem only the shares from this market (not the CPMM setUp balance)
        vm.prank(alice);
        market.redeemShares(id, yesShares);

        assertLe(collateral.balanceOf(alice) - before, totalCol);
    }

    // F-08
    function testFuzz_yul_calcFee(uint128 amount, uint16 bps) public view {
        bps = uint16(bound(bps, 0, 10000));
        assertEq(yul.calcFeeYul(amount, bps), yul.calcFeeSolidity(amount, bps));
    }

    // F-09
    function testFuzz_yul_amountOut(uint128 amIn, uint128 resIn, uint128 resOut) public view {
        vm.assume(resIn > 0 && resOut > 0 && amIn > 0);
        assertEq(yul.amountOutYul(amIn, resIn, resOut), yul.amountOutSolidity(amIn, resIn, resOut));
    }

    // F-10
    function testFuzz_yul_isPowerOfTwo(uint256 value) public view {
        assertEq(yul.isPowerOfTwoYul(value), yul.isPowerOfTwoSolidity(value));
    }
}
