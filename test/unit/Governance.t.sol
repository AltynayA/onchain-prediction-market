// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {GovernanceToken} from "../../contracts/governance/PredictionToken.sol";
import {MarketGovernor} from "../../contracts/governance/MarketGovernor.sol";
import {MarketTimelock} from "../../contracts/governance/MarketTimelock.sol";
import {IVotes} from "@openzeppelin/contracts/governance/utils/IVotes.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";

contract GovernanceTokenTest is Test {
    address team = makeAddr("team");
    address treasury = makeAddr("treasury");
    address community = makeAddr("community");
    address liquidity = makeAddr("liquidity");
    address gwen = makeAddr("gwen");

    GovernanceToken token;

    function setUp() public {
        token = new GovernanceToken(team, treasury, community, liquidity);
    }

    function test_totalSupply_is1Million() public view {
        assertEq(token.totalSupply(), 1_000_000 ether);
    }

    function test_votingPower_afterSelfDelegate() public {
        vm.prank(team);
        token.delegate(team);
        assertEq(token.getVotes(team), 400_000 ether);
    }
}

// Timelock configuration and delay checks
contract MarketTimelockTest is Test {
    address admin = makeAddr("admin");
    address proposer = makeAddr("proposer");
    address executor = makeAddr("executor");

    MarketTimelock timelock;
    uint256 constant MIN_DELAY = 2 days;

    function setUp() public {
        address[] memory proposers = new address[](1);
        address[] memory executors = new address[](1);
        proposers[0] = proposer;
        executors[0] = executor;
        timelock = new MarketTimelock(MIN_DELAY, proposers, executors, admin);
    }

    function test_minDelay_is2Days() public view {
        assertEq(timelock.getMinDelay(), 2 days);
    }

    function test_execute_beforeDelay_reverts() public {
        vm.prank(proposer);
        timelock.schedule(address(0), 0, "", bytes32(0), bytes32(0), MIN_DELAY);

        vm.prank(executor);
        vm.expectRevert();
        timelock.execute(address(0), 0, "", bytes32(0), bytes32(0));
    }
}

// Governor integration tests
contract MarketGovernorTest is Test {
    address team = makeAddr("team");
    address treasury = makeAddr("treasury");
    address community = makeAddr("community");
    address liquidity = makeAddr("liquidity");
    address gwen = makeAddr("gwen");

    GovernanceToken token;
    MarketTimelock timelock;
    MarketGovernor governor;

    function setUp() public {
        // deploy token
        token = new GovernanceToken(team, treasury, community, liquidity);

        // deploy timelock
        address[] memory proposers = new address[](0);
        address[] memory executors = new address[](1);
        executors[0] = address(0);
        timelock = new MarketTimelock(2 days, proposers, executors, address(this));

        // deploy governor
        governor = new MarketGovernor(IVotes(address(token)), TimelockController(payable(address(timelock))));

        // Governor needs proposer and canceller permissions
        timelock.grantRole(timelock.PROPOSER_ROLE(), address(governor));
        timelock.grantRole(timelock.CANCELLER_ROLE(), address(governor));
        timelock.renounceRole(timelock.DEFAULT_ADMIN_ROLE(), address(this));

        // gwen gets 5% (> threshold)
        vm.prank(community);
        token.transfer(gwen, 50_000 ether);
        vm.prank(gwen);
        token.delegate(gwen);

        vm.prank(team);
        token.delegate(team);

        vm.roll(block.number + 1);
    }

    function test_votingDelay_is1Day() public view {
        assertEq(governor.votingDelay(), 1 days);
    }

    function test_votingPeriod_is1Week() public view {
        assertEq(governor.votingPeriod(), 1 weeks);
    }

    function test_proposalThreshold_is1Percent() public view {
        // 1% of 1 mil ether
        assertEq(governor.proposalThreshold(), 10_000 ether);
    }

    function test_quorum_absolute_is4Percent() public view {
        // 4% of 1 mil ether
        assertEq(governor.quorum(block.number - 1), 40_000 ether);
    }
    
    function test_propose_belowThreshold_reverts() public {
        address poor = makeAddr("poor");
        vm.prank(liquidity);
        token.transfer(poor, 100 ether); // way below 10_000 ether threshold
        vm.prank(poor);
        token.delegate(poor);
        vm.roll(block.number + 1);

        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        targets[0] = address(0);

        vm.prank(poor);
        vm.expectRevert();
        governor.propose(targets, values, calldatas, "test");
    }
}
