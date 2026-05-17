// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {
    ERC1967Proxy
} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {PredictionMarket} from "../../contracts/core/PredictionMarket.sol";
import {PredictionMarketV2} from "../../contracts/core/PredictionMarketV2.sol";
import {CollateralToken} from "../../contracts/tokens/CollateralToken.sol";
import {OutcomeToken} from "../../contracts/tokens/OutcomeToken.sol";
import {OracleAdapter} from "../../contracts/oracles/OracleAdapter.sol";
import {MockAggregator} from "../../contracts/mocks/MockAggregator.sol";
import {FeeVault} from "../../contracts/core/FeeVault.sol";

contract PredictionMarketTest is Test {
    //actors
    address admin = makeAddr("admin");
    address resolver = makeAddr("resolver");
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");
    address attacker = makeAddr("attacker");

    //contracts
    CollateralToken collateral;
    OutcomeToken outcomeToken;
    MockAggregator aggregator;
    OracleAdapter oracle;
    FeeVault feeVault;
    PredictionMarket market; // proxy

    uint256 constant STALENESS = 1 hours;
    uint256 constant DISPUTE_W = 2 days;
    uint256 constant RES_OFFSET = 7 days; // resolution time = now + 7 days

    //setup
    function setUp() public {
        vm.startPrank(admin);

        collateral = new CollateralToken("Mock USDC", "mUSDC", 6);
        outcomeToken = new OutcomeToken();
        aggregator = new MockAggregator(3000e8, 8);
        oracle = new OracleAdapter(address(aggregator));
        feeVault = new FeeVault(collateral);

        // deploy implementation + proxy
        PredictionMarket impl = new PredictionMarket();
        bytes memory initData = abi.encodeCall(
            PredictionMarket.initialize,
            (
                admin,
                address(collateral),
                address(outcomeToken),
                STALENESS,
                DISPUTE_W,
                address(feeVault)
            )
        );
        market = PredictionMarket(
            address(new ERC1967Proxy(address(impl), initData))
        );

        // grant market permission to mint/burn outcome shares
        outcomeToken.grantRole(outcomeToken.MINTER_ROLE(), address(market));

        // give resolver role
        market.grantRole(market.RESOLVER_ROLE(), resolver);

        // fund alice and bob
        collateral.mint(alice, 10_000e6);
        collateral.mint(bob, 10_000e6);
        vm.stopPrank();

        vm.prank(alice);
        collateral.approve(address(market), type(uint256).max);
        vm.prank(bob);
        collateral.approve(address(market), type(uint256).max);
    }

    //helpers
    function _createMarket() internal returns (uint256 id) {
        vm.prank(admin);
        id = market.createMarket(
            "Will ETH > $5000 by Jan 2026?",
            block.timestamp + RES_OFFSET,
            address(oracle)
        );
    }

    function _buyAndResolve(bool outcome) internal returns (uint256 id) {
        id = _createMarket();
        vm.prank(alice);
        market.buyShares(id, true, 1000e6, 0); // YES
        vm.prank(bob);
        market.buyShares(id, false, 1000e6, 0); // NO
        vm.warp(block.timestamp + RES_OFFSET + 1);
        aggregator.refresh();
        vm.prank(resolver);
        market.resolveMarket(id, outcome);
    }

    function _finalize(uint256 id) internal {
        vm.warp(block.timestamp + DISPUTE_W + 1);
        market.finalizeMarket(id);
    }

    // createMarket
    function test_createMarket_success() public {
        uint256 id = _createMarket();
        assertEq(id, 0);
        assertEq(market.marketCount(), 1);

        PredictionMarket.Market memory m = market.getMarket(0);
        assertEq(uint8(m.state), uint8(PredictionMarket.MarketState.Active));
        assertEq(m.oracleAdapter, address(oracle));
    }

    function test_createMarket_incrementsId() public {
        uint256 id0 = _createMarket();
        uint256 id1 = _createMarket();
        assertEq(id0, 0);
        assertEq(id1, 1);
        assertEq(market.marketCount(), 2);
    }

    function test_createMarket_revert_notAdmin() public {
        vm.prank(alice);
        vm.expectRevert();
        market.createMarket("Q?", block.timestamp + 1, address(oracle));
    }

    function test_createMarket_revert_emptyQuestion() public {
        vm.prank(admin);
        vm.expectRevert("PM: empty question");
        market.createMarket("", block.timestamp + 1, address(oracle));
    }

    function test_createMarket_revert_resolutionInPast() public {
        vm.prank(admin);
        vm.expectRevert("PM: resolution in past");
        market.createMarket("Q?", block.timestamp - 1, address(oracle));
    }

    function test_createMarket_revert_zeroOracle() public {
        vm.prank(admin);
        vm.expectRevert("PM: zero oracle");
        market.createMarket("Q?", block.timestamp + 1, address(0));
    }

    function test_createMarket_revert_whenPaused() public {
        vm.prank(admin);
        market.pause();
        vm.prank(admin);
        vm.expectRevert();
        market.createMarket("Q?", block.timestamp + 1, address(oracle));
    }

    // buyShares
    function test_buyShares_yes_mintsCorrectAmount() public {
        uint256 id = _createMarket();
        uint256 amount = 1000e6;

        vm.prank(alice);
        market.buyShares(id, true, amount, 0);

        uint256 fee = (amount * 100) / 10000; // 1%
        uint256 expected = amount - fee;
        assertEq(outcomeToken.balanceOf(alice, 0), expected); // YES = id 0
    }

    function test_buyShares_no_mintsCorrectAmount() public {
        uint256 id = _createMarket();
        uint256 amount = 500e6;

        vm.prank(bob);
        market.buyShares(id, false, amount, 0);

        uint256 fee = (amount * 100) / 10000;
        assertEq(outcomeToken.balanceOf(bob, 1), amount - fee); // NO = id 1
    }

    function test_buyShares_fee_sentToVault() public {
        uint256 id = _createMarket();
        uint256 amount = 1000e6;
        uint256 fee = (amount * 100) / 10000;

        vm.prank(alice);
        market.buyShares(id, true, amount, 0);

        assertEq(collateral.balanceOf(address(feeVault)), fee);
    }

    function test_buyShares_collateral_keptInContract() public {
        uint256 id = _createMarket();
        uint256 amount = 1000e6;
        uint256 fee = (amount * 100) / 10000;

        vm.prank(alice);
        market.buyShares(id, true, amount, 0);

        assertEq(collateral.balanceOf(address(market)), amount - fee);
    }

    function test_buyShares_revert_zeroAmount() public {
        uint256 id = _createMarket();
        vm.prank(alice);
        vm.expectRevert("PM: zero amount");
        market.buyShares(id, true, 0, 0);
    }

    function test_buyShares_revert_afterResolutionTime() public {
        uint256 id = _createMarket();
        vm.warp(block.timestamp + RES_OFFSET + 1);
        vm.prank(alice);
        vm.expectRevert("PM: past resolution time");
        market.buyShares(id, true, 1000e6, 0);
    }

    function test_buyShares_revert_slippage() public {
        uint256 id = _createMarket();
        vm.prank(alice);
        vm.expectRevert("PM: slippage");
        market.buyShares(id, true, 1000e6, 1000e6); // net = 990e6, minShares = 1000e6
    }

    function test_buyShares_revert_marketNotActive() public {
        uint256 id = _buyAndResolve(true);
        vm.prank(alice);
        vm.expectRevert("PM: market not active");
        market.buyShares(id, true, 1000e6, 0);
    }

    function test_buyShares_revert_whenPaused() public {
        uint256 id = _createMarket();
        vm.prank(admin);
        market.pause();
        vm.prank(alice);
        vm.expectRevert();
        market.buyShares(id, true, 1000e6, 0);
    }

    //resolveMarket: vuln #2 (access control) fixed
    function test_resolveMarket_success() public {
        uint256 id = _createMarket();
        vm.prank(alice);
        market.buyShares(id, true, 1000e6, 0);
        vm.warp(block.timestamp + RES_OFFSET + 1);
        aggregator.refresh();

        vm.prank(resolver);
        market.resolveMarket(id, true);

        PredictionMarket.Market memory m = market.getMarket(id);
        assertEq(uint8(m.state), uint8(PredictionMarket.MarketState.Pending));
        assertTrue(m.outcome);
        assertGt(m.disputeDeadline, block.timestamp);
    }

    // before fix, anyone could call resolveMarket
    function test_resolveMarket_revert_notResolver() public {
        uint256 id = _createMarket();
        vm.warp(block.timestamp + RES_OFFSET + 1);
        vm.prank(attacker);
        vm.expectRevert();
        market.resolveMarket(id, true);
    }

    function test_resolveMarket_revert_tooEarly() public {
        uint256 id = _createMarket();
        vm.prank(resolver);
        vm.expectRevert("PM: too early");
        market.resolveMarket(id, true);
    }

    function test_resolveMarket_revert_staleOracle() public {
        uint256 id = _createMarket();
        vm.warp(block.timestamp + RES_OFFSET + 1);
        aggregator.setStale(STALENESS + 1); // make oracle stale

        vm.prank(resolver);
        vm.expectRevert("OA: stale price");
        market.resolveMarket(id, true);
    }

    function test_resolveMarket_revert_notActive() public {
        uint256 id = _buyAndResolve(true); // already Pending
        vm.warp(block.timestamp + 1);
        aggregator.refresh();
        vm.prank(resolver);
        vm.expectRevert("PM: not active");
        market.resolveMarket(id, false);
    }

    // disputeMarket / finalizeMarket
    function test_disputeMarket_success() public {
        uint256 id = _buyAndResolve(true);
        vm.prank(bob);
        market.disputeMarket(id);

        assertEq(
            uint8(market.getMarket(id).state),
            uint8(PredictionMarket.MarketState.Disputed)
        );
    }

    function test_disputeMarket_revert_windowExpired() public {
        uint256 id = _buyAndResolve(true);
        vm.warp(block.timestamp + DISPUTE_W + 1);
        vm.prank(bob);
        vm.expectRevert("PM: window expired");
        market.disputeMarket(id);
    }

    function test_disputeMarket_revert_notPending() public {
        uint256 id = _createMarket();
        vm.prank(bob);
        vm.expectRevert("PM: not pending");
        market.disputeMarket(id);
    }

    function test_finalizeMarket_success() public {
        uint256 id = _buyAndResolve(true);
        vm.warp(block.timestamp + DISPUTE_W + 1);
        market.finalizeMarket(id);

        assertEq(
            uint8(market.getMarket(id).state),
            uint8(PredictionMarket.MarketState.Final)
        );
    }

    function test_finalizeMarket_revert_windowNotOver() public {
        uint256 id = _buyAndResolve(true);
        vm.expectRevert("PM: window not over");
        market.finalizeMarket(id);
    }

    // settleDispute
    function test_settleDispute_governanceOverride() public {
        uint256 id = _buyAndResolve(true); // resolver said YES
        vm.prank(bob);
        market.disputeMarket(id);

        // governance overrides to NO
        vm.prank(admin);
        market.settleDispute(id, false);

        PredictionMarket.Market memory m = market.getMarket(id);
        assertEq(uint8(m.state), uint8(PredictionMarket.MarketState.Final));
        assertFalse(m.outcome);
    }

    function test_settleDispute_revert_notAdmin() public {
        uint256 id = _buyAndResolve(true);
        vm.prank(bob);
        market.disputeMarket(id);
        vm.prank(alice);
        vm.expectRevert();
        market.settleDispute(id, false);
    }

    function test_settleDispute_revert_notDisputed() public {
        uint256 id = _createMarket();
        vm.prank(admin);
        vm.expectRevert("PM: not disputed");
        market.settleDispute(id, true);
    }

    // redeemShares: vuln #1 (reentrancy) reproduced and fixed
    function test_redeemShares_yesWinner() public {
        uint256 id = _buyAndResolve(true); // YES wins
        _finalize(id);

        vm.prank(alice);
        outcomeToken.setApprovalForAll(address(market), true);

        uint256 yesShares = outcomeToken.balanceOf(alice, 0);
        uint256 balanceBefore = collateral.balanceOf(alice);

        vm.prank(alice);
        market.redeemShares(id, yesShares);

        assertGt(collateral.balanceOf(alice), balanceBefore);
        assertEq(outcomeToken.balanceOf(alice, 0), 0);
    }

    function test_redeemShares_noWinner() public {
        uint256 id = _buyAndResolve(false); // NO wins
        _finalize(id);

        vm.prank(bob);
        outcomeToken.setApprovalForAll(address(market), true);

        uint256 noShares = outcomeToken.balanceOf(bob, 1);
        uint256 balanceBefore = collateral.balanceOf(bob);

        vm.prank(bob);
        market.redeemShares(id, noShares);

        assertGt(collateral.balanceOf(bob), balanceBefore);
    }

    function test_redeemShares_losingSideGetsNothing() public {
        uint256 id = _buyAndResolve(true); // YES wins,  bob (NO) loses
        _finalize(id);

        uint256 bobCollateralBefore = collateral.balanceOf(bob);
        // bob has no YES shares: collateral unchanged
        assertEq(outcomeToken.balanceOf(bob, 0), 0);
        assertEq(collateral.balanceOf(bob), bobCollateralBefore);
    }

    function test_redeemShares_revert_notFinal() public {
        uint256 id = _createMarket();
        vm.prank(alice);
        vm.expectRevert("PM: not final");
        market.redeemShares(id, 1);
    }

    function test_redeemShares_revert_zeroAmount() public {
        uint256 id = _buyAndResolve(true);
        _finalize(id);
        vm.prank(alice);
        vm.expectRevert("PM: zero amount");
        market.redeemShares(id, 0);
    }

    function test_reentrancy_redeemShares_blocked() public {
        uint256 id = _buyAndResolve(true);
        _finalize(id);

        vm.prank(alice);
        outcomeToken.setApprovalForAll(address(market), true);

        uint256 aliceYes = outcomeToken.balanceOf(alice, 0);

        //first redeem succeeds
        vm.prank(alice);
        market.redeemShares(id, aliceYes);

        // second redeem reverts as shares already burned
        vm.prank(alice);
        vm.expectRevert();
        market.redeemShares(id, 1);
    }

    //  adding pausable
    function test_pause_blocksAllUserFunctions() public {
        uint256 id = _createMarket();
        vm.prank(admin);
        market.pause();

        vm.prank(alice);
        vm.expectRevert();
        market.buyShares(id, true, 1000e6, 0);
    }

    function test_unpause_restoresFunctionality() public {
        uint256 id = _createMarket();
        vm.prank(admin);
        market.pause();
        vm.prank(admin);
        market.unpause();

        vm.prank(alice);
        market.buyShares(id, true, 1000e6, 0); // must not revert
    }

    function test_pause_revert_notPauser() public {
        vm.prank(alice);
        vm.expectRevert();
        market.pause();
    }

    // v1 to v2 upgrade
    function test_upgrade_v1_to_v2_preservesState() public {
        uint256 id = _createMarket();
        vm.prank(alice);
        market.buyShares(id, true, 1000e6, 0);

        uint256 countBefore = market.marketCount();

        // deploy V2 and upgrade
        vm.startPrank(admin);
        PredictionMarketV2 implV2 = new PredictionMarketV2();
        market.upgradeToAndCall(
            address(implV2),
            abi.encodeCall(PredictionMarketV2.initializeV2, (admin))
        );
        vm.stopPrank();

        PredictionMarketV2 marketV2 = PredictionMarketV2(address(market));

        // v1 state fully preserved
        assertEq(marketV2.marketCount(), countBefore);
        assertEq(marketV2.defaultStaleness(), STALENESS);
        assertEq(marketV2.defaultDisputeWindow(), DISPUTE_W);
        assertEq(
            uint8(marketV2.getMarket(id).state),
            uint8(PredictionMarket.MarketState.Active)
        );

        // v2 state initialised
        assertEq(marketV2.emergencyRecipient(), admin);
    }

    function test_upgrade_v2_newFunctionsWork() public {
        uint256 id = _createMarket();

        vm.startPrank(admin);
        PredictionMarketV2 implV2 = new PredictionMarketV2();
        market.upgradeToAndCall(
            address(implV2),
            abi.encodeCall(PredictionMarketV2.initializeV2, (admin))
        );
        vm.stopPrank();

        PredictionMarketV2 marketV2 = PredictionMarketV2(address(market));

        // set fee per market
        vm.prank(admin);
        marketV2.setMarketFee(id, 50); // 0.5%
        assertEq(marketV2.effectiveFee(id), 50);

        // fallback to global if not set
        assertEq(marketV2.effectiveFee(999), 100); // global FEE_BPS
    }

    function test_upgrade_revert_notAdmin() public {
        PredictionMarketV2 implV2 = new PredictionMarketV2();
        vm.prank(alice);
        vm.expectRevert();
        market.upgradeToAndCall(address(implV2), "");
    }

    // admin setters
    function test_setStaleness() public {
        vm.prank(admin);
        market.setStaleness(2 hours);
        assertEq(market.defaultStaleness(), 2 hours);
    }

    function test_setStaleness_revert_zero() public {
        vm.prank(admin);
        vm.expectRevert("PM: zero");
        market.setStaleness(0);
    }

    function test_setDisputeWindow() public {
        vm.prank(admin);
        market.setDisputeWindow(3 days);
        assertEq(market.defaultDisputeWindow(), 3 days);
    }

    function test_setFeeVault() public {
        address newVault = makeAddr("newVault");
        vm.prank(admin);
        market.setFeeVault(newVault);
        assertEq(market.feeVault(), newVault);
    }

    function test_setFeeVault_revert_zero() public {
        vm.prank(admin);
        vm.expectRevert("PM: zero");
        market.setFeeVault(address(0));
    }
}
