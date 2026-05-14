// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import {PredictionMarket} from "../contracts/core/PredictionMarket.sol";
import {MarketTimelock} from "../contracts/governance/MarketTimelock.sol";
import {MarketGovernor} from "../contracts/governance/MarketGovernor.sol";

// post-deployment sanity check
// run after Deploy.s.sol with deployed addresses in .env:
//   source .env && forge script script/Verify.s.sol:Verify --rpc-url $BASE_SEPOLIA_RPC_URL -vvvv
contract Verify is Script {
    uint256 constant EXPECTED_TIMELOCK_DELAY = 2 days;
    uint256 constant EXPECTED_VOTING_DELAY = 1 days;
    uint256 constant EXPECTED_VOTING_PERIOD = 1 weeks;
    uint256 constant EXPECTED_QUORUM_FRACTION = 4;

    function run() external view {
        address marketAddr = vm.envAddress("MARKET_ADDRESS");
        address timelockAddr = vm.envAddress("TIMELOCK_ADDRESS");
        address governorAddr = vm.envAddress("GOVERNOR_ADDRESS");
        address deployer = vm.envAddress("DEPLOYER_ADDRESS");

        PredictionMarket market = PredictionMarket(marketAddr);
        MarketTimelock timelock = MarketTimelock(payable(timelockAddr));
        MarketGovernor governor = MarketGovernor(payable(governorAddr));

        console.log("post-deployment verification");

        // timelock is admin of prediction market
        bool timelockIsAdmin = market.hasRole(market.DEFAULT_ADMIN_ROLE(), timelockAddr);
        console.log("timelock is market admin:      ", timelockIsAdmin);
        require(timelockIsAdmin, "FAIL: timelock not market admin");

        // deployer no longer has admin on market
        bool deployerHasAdmin = market.hasRole(market.DEFAULT_ADMIN_ROLE(), deployer);
        console.log("deployer has market admin:     ", deployerHasAdmin);
        require(!deployerHasAdmin, "FAIL: deployer still has market admin");

        // timelock delay is 2 days
        uint256 delay = timelock.getMinDelay();
        console.log("timelock min delay (seconds):  ", delay);
        require(delay == EXPECTED_TIMELOCK_DELAY, "FAIL: wrong timelock delay");

        // governor is proposer on timelock
        bool govIsProposer = timelock.hasRole(timelock.PROPOSER_ROLE(), governorAddr);
        console.log("governor is timelock proposer: ", govIsProposer);
        require(govIsProposer, "FAIL: governor not timelock proposer");

        // deployer no longer has admin on timelock
        bool deployerHasTimelockAdmin = timelock.hasRole(timelock.DEFAULT_ADMIN_ROLE(), deployer);
        console.log("deployer has timelock admin:   ", deployerHasTimelockAdmin);
        require(!deployerHasTimelockAdmin, "FAIL: deployer still has timelock admin");

        // governor parameters match spec
        uint256 votingDelay = governor.votingDelay();
        uint256 votingPeriod = governor.votingPeriod();
        uint256 quorum = governor.quorumNumerator();
        console.log("voting delay (seconds):        ", votingDelay);
        console.log("voting period (seconds):       ", votingPeriod);
        console.log("quorum fraction (%):           ", quorum);
        require(votingDelay == EXPECTED_VOTING_DELAY, "FAIL: wrong voting delay");
        require(votingPeriod == EXPECTED_VOTING_PERIOD, "FAIL: wrong voting period");
        require(quorum == EXPECTED_QUORUM_FRACTION, "FAIL: wrong quorum");

        // market config sanity check
        uint256 staleness = market.defaultStaleness();
        uint256 disputeWindow = market.defaultDisputeWindow();
        console.log("oracle staleness (seconds):    ", staleness);
        console.log("dispute window (seconds):      ", disputeWindow);
        require(staleness > 0, "FAIL: zero staleness");
        require(disputeWindow > 0, "FAIL: zero dispute window");

        console.log("all checks passed ");
    }
}
