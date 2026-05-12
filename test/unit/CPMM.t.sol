// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {CPMM} from "../../contracts/core/CPMM.sol";
import {OutcomeToken} from "../../contracts/tokens/OutcomeToken.sol";

contract CPMMTest is Test {
    //actors
    address admin = makeAddr("admin");
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");

    //contracts
    OutcomeToken token;
    CPMM cpmm;

    uint256 constant YES = 0;
    uint256 constant NO = 1;

    //setup
    function setUp() public {
        vm.startPrank(admin);
        token = new OutcomeToken();
        cpmm = new CPMM(address(token));

        token.grantRole(token.MINTER_ROLE(), admin);

        // mint generous balances for testers
        token.mint(alice, YES, 500_000e18);
        token.mint(alice, NO, 500_000e18);
        token.mint(bob, YES, 500_000e18);
        token.mint(bob, NO, 500_000e18);
        vm.stopPrank();

        // approve CPMM as ERC-1155 operator
        vm.prank(alice);
        token.setApprovalForAll(address(cpmm), true);

        vm.prank(bob);
        token.setApprovalForAll(address(cpmm), true);
    }

// addLiquidity tests
    function test_addLiquidity_firstDeposit_mintsLp() public {
        vm.prank(alice);
        uint256 lp = cpmm.addLiquidity(10_000e18, 10_000e18, 0);

        assertGt(lp, 0);
        assertEq(cpmm.reserveYes(), 10_000e18);
        assertEq(cpmm.reserveNo(),  10_000e18);
        assertEq(cpmm.lpBalance(alice), lp);
        assertEq(cpmm.totalLpSupply(), lp + 1000); // 1000 = MINIMUM_LIQUIDITY
    }

    function test_addLiquidity_minimumLiquidity_lockedToAddress1() public {
        vm.prank(alice);
        cpmm.addLiquidity(10_000e18, 10_000e18, 0);

        assertEq(cpmm.lpBalance(address(1)), 1000);
    }

    function test_addLiquidity_subsequentDeposit_proportional() public {
        vm.prank(alice);
        uint256 lp1 = cpmm.addLiquidity(10_000e18, 10_000e18, 0);

        uint256 totalBefore = cpmm.totalLpSupply();

        vm.prank(bob);
        uint256 lp2 = cpmm.addLiquidity(5_000e18, 5_000e18, 0);

        assertGt(lp2, 0);
        assertEq(cpmm.totalLpSupply(), totalBefore + lp2);
        assertApproxEqRel(lp2, lp1 / 2, 0.01e18); // roughly half of alice's LP
    }

    function test_addLiquidity_revert_zeroYes() public {
        vm.prank(alice);
        vm.expectRevert("CPMM: zero input");
        cpmm.addLiquidity(0, 1000e18, 0);
    }

    function test_addLiquidity_revert_zeroNo() public {
        vm.prank(alice);
        vm.expectRevert("CPMM: zero input");
        cpmm.addLiquidity(1000e18, 0, 0);
    }

    function test_addLiquidity_revert_slippage() public {
        vm.prank(alice);
        vm.expectRevert("CPMM: slippage");
        cpmm.addLiquidity(10_000e18, 10_000e18, type(uint256).max);
    }

    function test_addLiquidity_takesTokensFromCaller() public {
        uint256 yesBefore = token.balanceOf(alice, YES);
        uint256 noBefore  = token.balanceOf(alice, NO);

        vm.prank(alice);
        cpmm.addLiquidity(10_000e18, 8_000e18, 0);

        assertEq(token.balanceOf(alice, YES), yesBefore - 10_000e18);
        assertEq(token.balanceOf(alice, NO),  noBefore  - 8_000e18);
    }

//removeLiquidity
        function test_removeLiquidity_returnsTokens() public {
        vm.prank(alice);
        uint256 lp = cpmm.addLiquidity(10_000e18, 10_000e18, 0);

        uint256 yesBefore = token.balanceOf(alice, YES);
        uint256 noBefore  = token.balanceOf(alice, NO);

        vm.prank(alice);
        cpmm.removeLiquidity(lp, 0, 0);

        assertGt(token.balanceOf(alice, YES), yesBefore);
        assertGt(token.balanceOf(alice, NO),  noBefore);
        assertEq(cpmm.lpBalance(alice), 0);
    }

    function test_removeLiquidity_proportionalToReserves() public {
        vm.prank(alice);
        uint256 lp = cpmm.addLiquidity(10_000e18, 6_000e18, 0);

        // Read pool state AFTER deposit for correct expected calculation
        uint256 totalLp = cpmm.totalLpSupply();
        uint256 resYes = cpmm.reserveYes();
        uint256 lpHalf = lp / 2;
        uint256 expectedYes = (lpHalf * resYes) / totalLp;

        uint256 yesBefore = token.balanceOf(alice, YES);

        vm.prank(alice);
        cpmm.removeLiquidity(lpHalf, 0, 0);

        // Allow 1 wei rounding tolerance
        assertApproxEqAbs(
            token.balanceOf(alice, YES) - yesBefore,
            expectedYes,
            1
        );
    }

    function test_removeLiquidity_revert_insufficientLp() public {
        vm.prank(alice);
        cpmm.addLiquidity(10_000e18, 10_000e18, 0);

        vm.prank(alice);
        vm.expectRevert("CPMM: insufficient lp");
        cpmm.removeLiquidity(type(uint256).max, 0, 0);
    }

    function test_removeLiquidity_revert_zeroLp() public {
        vm.prank(alice);
        vm.expectRevert("CPMM: zero lp");
        cpmm.removeLiquidity(0, 0, 0);
    }

    function test_removeLiquidity_revert_slippageYes() public {
        vm.prank(alice);
        uint256 lp = cpmm.addLiquidity(10_000e18, 10_000e18, 0);

        vm.prank(alice);
        vm.expectRevert("CPMM: slippage yes");
        cpmm.removeLiquidity(lp, type(uint256).max, 0);
    }

    function test_removeLiquidity_revert_slippageNo() public {
        vm.prank(alice);
        uint256 lp = cpmm.addLiquidity(10_000e18, 10_000e18, 0);

        vm.prank(alice);
        vm.expectRevert("CPMM: slippage no");
        cpmm.removeLiquidity(lp, 0, type(uint256).max);
    }

//swap
    function _seedPool() internal {
        vm.prank(alice);
        cpmm.addLiquidity(10_000e18, 10_000e18, 0);
    }

    function test_swap_yesForNo_receivesNo() public {
        _seedPool();
        uint256 noBefore = token.balanceOf(bob, NO);

        vm.prank(bob);
        uint256 out = cpmm.swap(true, 100e18, 0);

        assertGt(out, 0);
        assertEq(token.balanceOf(bob, NO), noBefore + out);
    }

    function test_swap_noForYes_receivesYes() public {
        _seedPool();
        uint256 yesBefore = token.balanceOf(bob, YES);

        vm.prank(bob);
        uint256 out = cpmm.swap(false, 100e18, 0);

        assertGt(out, 0);
        assertEq(token.balanceOf(bob, YES), yesBefore + out);
    }

    function test_swap_outputLessThanInput_dueToFee() public {
        _seedPool();
        vm.prank(bob);
        uint256 out = cpmm.swap(true, 100e18, 0);
        // with equal reserves, output should be slightly less than input (fee + price impact)
        assertLt(out, 100e18);
    }

    function test_swap_kInvariant_maintained() public {
        _seedPool();
        uint256 kBefore = cpmm.reserveYes() * cpmm.reserveNo();

        vm.prank(bob);
        cpmm.swap(true, 100e18, 0);

        uint256 kAfter = cpmm.reserveYes() * cpmm.reserveNo();
        assertGe(kAfter, kBefore); // k must never decrease
    }

    function test_swap_reservesUpdatedCorrectly() public {
        _seedPool();
        uint256 resYesBefore = cpmm.reserveYes();
        uint256 resNoBefore  = cpmm.reserveNo();

        vm.prank(bob);
        uint256 out = cpmm.swap(true, 100e18, 0); // YES->NO

        assertEq(cpmm.reserveYes(), resYesBefore + 100e18);
        assertEq(cpmm.reserveNo(),  resNoBefore  - out);
    }

    function test_swap_revert_zeroInput() public {
        _seedPool();
        vm.prank(bob);
        vm.expectRevert("CPMM: zero input");
        cpmm.swap(true, 0, 0);
    }

    function test_swap_revert_noLiquidity() public {
        vm.prank(bob);
        vm.expectRevert("CPMM: no liquidity");
        cpmm.swap(true, 100e18, 0);
    }

    function test_swap_revert_slippage() public {
        _seedPool();
        vm.prank(bob);
        vm.expectRevert("CPMM: slippage");
        cpmm.swap(true, 100e18, type(uint256).max);
    }

//getAmountOut
    function test_getAmountOut_matchesActualSwap() public {
        _seedPool();
        uint256 preview = cpmm.getAmountOut(true, 200e18);

        vm.prank(bob);
        uint256 actual = cpmm.swap(true, 200e18, 0);

        assertEq(preview, actual);
    }

    function test_getAmountOut_revert_zeroInput() public {
        _seedPool();
        vm.expectRevert("CPMM: zero input");
        cpmm.getAmountOut(true, 0);
    }

    function test_getAmountOut_revert_noLiquidity() public {
        vm.expectRevert("CPMM: no liquidity");
        cpmm.getAmountOut(true, 100e18);
    }

//impliedProbabilityYes
    function test_impliedProbability_balancedPool() public {
        _seedPool();
        uint256 prob = cpmm.impliedProbabilityYes();
        // Equal reserves -> 50%
        assertApproxEqAbs(prob, 0.5e18, 1e15);
    }

    function test_impliedProbability_afterSwap_shifts() public {
        _seedPool();
        vm.prank(bob); cpmm.swap(true, 1000e18, 0); // buy YES -> NO gets scarce -> YES prob drops

        uint256 prob = cpmm.impliedProbabilityYes();
        assertLt(prob, 0.5e18); // YES became less likely after buying it
    }

    function test_impliedProbability_emptyPool_returnsZero() public {
        assertEq(cpmm.impliedProbabilityYes(), 0);
    }
}
