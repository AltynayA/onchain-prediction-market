
// test/integration
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {GovernanceToken} from "../../contracts/governance/PredictionToken.sol";
import {MarketGovernor} from "../../contracts/governance/MarketGovernor.sol";
import {MarketTimelock} from "../../contracts/governance/MarketTimelock.sol";
import {IVotes} from "@openzeppelin/contracts/governance/utils/IVotes.sol";
import {IGovernor} from "@openzeppelin/contracts/governance/IGovernor.sol";
import {
    TimelockController
} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {
    ERC1967Proxy
} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {PredictionMarket} from "../../contracts/core/PredictionMarket.sol";
import {CollateralToken} from "../../contracts/tokens/CollateralToken.sol";
import {OutcomeToken} from "../../contracts/tokens/OutcomeToken.sol";
import {FeeVault} from "../../contracts/core/FeeVault.sol";
import {MockAggregator} from "../../contracts/mocks/MockAggregator.sol";
import {OracleAdapter} from "../../contracts/oracles/OracleAdapter.sol";

// full governance lifecycle test (

//propose -> vote -> queue -> execute
contract GovernanceE2ETest is Test {
    // actors
    address deployer = makeAddr("deployer");
    address team = makeAddr("team");
    address treasury = makeAddr("treasury");
    address community = makeAddr("community");
    address liquidity = makeAddr("liquidity");
    address gwen = makeAddr("gwen"); // 10% whale — proposes + votes YES
    address peter = makeAddr("peter"); // 2%  — votes NO

    // contracts
    GovernanceToken token;
    MarketTimelock timelock;
    MarketGovernor governor;
    PredictionMarket market;
    CollateralToken collateral;
    OutcomeToken outcomeToken;
    FeeVault feeVault;
    MockAggregator aggregator;
    OracleAdapter oracle;

    uint256 constant TIMELOCK_DELAY = 2 days;
    uint256 constant NEW_DISPUTE_WINDOW = 3 days;

    // setup
    function setUp() public {
        vm.startPrank(deployer);

        // 1) governance token
        token = new GovernanceToken(team, treasury, community, liquidity);

        // 2) timelock: deployer is temp admin
        address[] memory proposers = new address[](0);
        address[] memory executors = new address[](1);
        executors[0] = address(0); // open execution
        timelock = new MarketTimelock(
            TIMELOCK_DELAY,
            proposers,
            executors,
            deployer
        );

        // 3) governor
        governor = new MarketGovernor(
            IVotes(address(token)),
            TimelockController(payable(address(timelock)))
        );

        // 4) wire governor into timelock
        timelock.grantRole(timelock.PROPOSER_ROLE(), address(governor));
        timelock.grantRole(timelock.CANCELLER_ROLE(), address(governor));

        // 5) deploy PredictionMarket -> Timelock is admin
        collateral = new CollateralToken("mUSDC", "mUSDC", 6);
        outcomeToken = new OutcomeToken();
        aggregator = new MockAggregator(3000e8, 8);
        oracle = new OracleAdapter(address(aggregator));
        feeVault = new FeeVault(collateral);

        PredictionMarket impl = new PredictionMarket();
        market = PredictionMarket(
            address(
                new ERC1967Proxy(
                    address(impl),
                    abi.encodeCall(
                        PredictionMarket.initialize,
                        (
                            address(timelock), // ← Timelock is admin, not deployer
                            address(collateral),
                            address(outcomeToken),
                            1 hours,
                            2 days,
                            address(feeVault)
                        )
                    )
                )
            )
        );

        // 6) Rrenounce deployer admin -> only admin is timelock
        timelock.renounceRole(timelock.DEFAULT_ADMIN_ROLE(), deployer);

        vm.stopPrank();

        // 7) distribute tokens and delegate
        vm.prank(community);
        token.transfer(gwen, 100_000 ether); //10%
        vm.prank(gwen);
        token.delegate(gwen);

        vm.prank(liquidity);
        token.transfer(peter, 20_000 ether); //2%
        vm.prank(peter);
        token.delegate(peter);

        vm.prank(team);
        token.delegate(team); // 40%

        vm.prank(treasury);
        token.delegate(treasury); // 30%

        vm.roll(block.number + 1); // snapshot voting power
    }

    // helpers
    function _buildProposal()
        internal
        view
        returns (
            address[] memory targets,
            uint256[] memory values,
            bytes[] memory calldatas,
            string memory description
        )
    {
        targets = new address[](1);
        values = new uint256[](1);
        calldatas = new bytes[](1);

        targets[0] = address(market);
        calldatas[0] = abi.encodeCall(
            PredictionMarket.setDisputeWindow,
            (NEW_DISPUTE_WINDOW)
        );
        description = "Proposal: increase dispute window from 2 to 3 days";
    }

    // full lifecycle

    function test_governance_propose_vote_queue_execute() public {
        (
            address[] memory targets,
            uint256[] memory values,
            bytes[] memory calldatas,
            string memory description
        ) = _buildProposal();

        // propose
        vm.prank(gwen);
        uint256 proposalId = governor.propose(
            targets,
            values,
            calldatas,
            description
        );

        assertEq(
            uint8(governor.state(proposalId)),
            uint8(IGovernor.ProposalState.Pending)
        );

        // voting delay
        vm.roll(block.number + governor.votingDelay() + 1);

        assertEq(
            uint8(governor.state(proposalId)),
            uint8(IGovernor.ProposalState.Active)
        );

        // vote
        vm.prank(gwen);
        governor.castVote(proposalId, 1); // for  100k
        vm.prank(team);
        governor.castVote(proposalId, 1); // for  400k
        vm.prank(peter);
        governor.castVote(proposalId, 0); // against 20k

        (uint256 against, uint256 forVotes, ) = governor.proposalVotes(
            proposalId
        );
        assertEq(forVotes, 500_000 ether);
        assertEq(against, 20_000 ether);

        // voting ends
        vm.roll(block.number + governor.votingPeriod() + 1);

        assertEq(
            uint8(governor.state(proposalId)),
            uint8(IGovernor.ProposalState.Succeeded)
        );

        // queue
        bytes32 descHash = keccak256(bytes(description));
        governor.queue(targets, values, calldatas, descHash);

        assertEq(
            uint8(governor.state(proposalId)),
            uint8(IGovernor.ProposalState.Queued)
        );

        // timelock delay
        vm.warp(block.timestamp + TIMELOCK_DELAY + 1);

        // execute
        governor.execute(targets, values, calldatas, descHash);

        assertEq(
            uint8(governor.state(proposalId)),
            uint8(IGovernor.ProposalState.Executed)
        );

        // verifying
        assertEq(market.defaultDisputeWindow(), NEW_DISPUTE_WINDOW);
    }

    // defeat:quorum not reached
    function test_governance_defeated_quorumNotReached() public {
        (
            address[] memory targets,
            uint256[] memory values,
            bytes[] memory calldatas,
            string memory description
        ) = _buildProposal();

        vm.prank(gwen);
        uint256 proposalId = governor.propose(
            targets,
            values,
            calldatas,
            description
        );

        vm.roll(block.number + governor.votingDelay() + 1);

        // peter votes for (20k = 2%) (quorum requires 40k = 4%
        vm.prank(peter);
        governor.castVote(proposalId, 1);

        vm.roll(block.number + governor.votingPeriod() + 1);

        assertEq(
            uint8(governor.state(proposalId)),
            uint8(IGovernor.ProposalState.Defeated)
        );
    }

    // defeat: against wins
    function test_governance_defeated_againstWins() public {
        (
            address[] memory targets,
            uint256[] memory values,
            bytes[] memory calldatas,
            string memory description
        ) = _buildProposal();

        vm.prank(gwen);
        uint256 proposalId = governor.propose(
            targets,
            values,
            calldatas,
            description
        );

        vm.roll(block.number + governor.votingDelay() + 1);

        vm.prank(treasury);
        governor.castVote(proposalId, 0); // against 300k
        vm.prank(gwen);
        governor.castVote(proposalId, 1); // for 100k

        vm.roll(block.number + governor.votingPeriod() + 1);

        assertEq(
            uint8(governor.state(proposalId)),
            uint8(IGovernor.ProposalState.Defeated)
        );
    }

    // execute before timelock delay reverts
    function test_governance_cannotExecuteBeforeTimelockDelay() public {
        (
            address[] memory targets,
            uint256[] memory values,
            bytes[] memory calldatas,
            string memory description
        ) = _buildProposal();

        vm.prank(gwen);
        uint256 proposalId = governor.propose(
            targets,
            values,
            calldatas,
            description
        );

        vm.roll(block.number + governor.votingDelay() + 1);

        vm.prank(gwen);
        governor.castVote(proposalId, 1);
        vm.prank(team);
        governor.castVote(proposalId, 1);

        vm.roll(block.number + governor.votingPeriod() + 1);

        bytes32 descHash = keccak256(bytes(description));
        governor.queue(targets, values, calldatas, descHash);

        // trying to execute immediately —> timelock delay has not elapsed
        vm.expectRevert();
        governor.execute(targets, values, calldatas, descHash);
    }

    // timelock market control
    function test_timelock_isAdminOfMarket() public view {
        assertTrue(
            market.hasRole(market.DEFAULT_ADMIN_ROLE(), address(timelock))
        );
    }

    function test_directCall_toMarket_reverts_forNonTimelock() public {
        vm.prank(gwen);
        vm.expectRevert();
        market.setDisputeWindow(5 days);
    }
}
