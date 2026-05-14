// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {CollateralToken} from "../contracts/tokens/CollateralToken.sol";
import {OutcomeToken} from "../contracts/tokens/OutcomeToken.sol";
import {FeeVault} from "../contracts/core/FeeVault.sol";
import {CPMM} from "../contracts/core/CPMM.sol";
import {PredictionMarket} from "../contracts/core/PredictionMarket.sol";
import {MarketFactory} from "../contracts/core/MarketFactory.sol";
import {GovernanceToken} from "../contracts/governance/PredictionToken.sol";
import {MarketTimelock} from "../contracts/governance/MarketTimelock.sol";
import {MarketGovernor} from "../contracts/governance/MarketGovernor.sol";
import {IVotes} from "@openzeppelin/contracts/governance/utils/IVotes.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";


contract Deploy is Script {

    // token distribution (must sum to 1 mil ether)
    uint256 constant TEAM_SHARE      = 400_000 ether;
    uint256 constant TREASURY_SHARE  = 300_000 ether;
    uint256 constant COMMUNITY_SHARE = 200_000 ether;
    uint256 constant LIQUIDITY_SHARE = 100_000 ether;

    // governance parameters (must match spec)
    uint256 constant TIMELOCK_DELAY  = 2 days;

    // oracle parameters
    uint256 constant STALENESS       = 1 hours;
    uint256 constant DISPUTE_WINDOW  = 2 days;

    function run() external {
        // load deployer from private key in env
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address deployer    = vm.addr(deployerKey);

        console.log("deployer:  ", deployer);
        console.log("chain id:  ", block.chainid);

        vm.startBroadcast(deployerKey);

        // 1) collateral token (mock usdc for testnet)
        CollateralToken collateral = new CollateralToken("Mock USDC", "mUSDC", 6);
        console.log("CollateralToken:", address(collateral));

        // 2) outcome token (erc1155 YES/NO shares)
        OutcomeToken outcomeToken = new OutcomeToken();
        console.log("OutcomeToken:   ", address(outcomeToken));

        // 3.) fee vault (erc4626 collateral as asset)
        FeeVault feeVault = new FeeVault(IERC20(address(collateral)));
        console.log("FeeVault:       ", address(feeVault));

        // 4) prediction market implementation + proxy
        //    deployer is temporary admin —> transferred to timelock in step 10
        PredictionMarket impl = new PredictionMarket();
        PredictionMarket market = PredictionMarket(address(new ERC1967Proxy(
            address(impl),
            abi.encodeCall(PredictionMarket.initialize, (
                deployer,               // temp admin
                address(collateral),
                address(outcomeToken),
                STALENESS,
                DISPUTE_WINDOW,
                address(feeVault)
            ))
        )));
        console.log("PredictionMarket impl:  ", address(impl));
        console.log("PredictionMarket proxy: ", address(market));

        // 5) market factory (create + create2)
        MarketFactory factory = new MarketFactory(
            deployer,
            address(collateral),
            address(outcomeToken),
            address(feeVault),
            STALENESS,
            DISPUTE_WINDOW
        );
        console.log("MarketFactory:  ", address(factory));

        // 6) cpmm
        CPMM cpmm = new CPMM(address(outcomeToken));
        console.log("CPMM:           ", address(cpmm));

        // 7) governance token (ERC20Votes + ERC20Permit)
        //    deployer receives all allocations — distribute after deployment
        GovernanceToken govToken = new GovernanceToken(
            deployer,   // team      40%
            deployer,   // treasury  30%
            deployer,   // community 20%
            deployer    // liquidity 10%
        );
        console.log("GovernanceToken:", address(govToken));

        // 8. timelock (2day min delat, no proposers yet —> governor added next)
        address[] memory proposers = new address[](0);
        address[] memory executors = new address[](1);
        executors[0] = address(0); // open execution — anyone can execute after delay
        MarketTimelock timelock = new MarketTimelock(
            TIMELOCK_DELAY,
            proposers,
            executors,
            deployer    // temporary admin
        );
        console.log("MarketTimelock: ", address(timelock));

        // 9) governor (1d delay, 1w period, 4% quorum, 1% threshold)
        MarketGovernor governor = new MarketGovernor(
            IVotes(address(govToken)),
            TimelockController(payable(address(timelock)))
        );
        console.log("MarketGovernor: ", address(governor));

        // 10) wire roles
        // governor gets PROPOSER + CANCELLER on timelock
        timelock.grantRole(timelock.PROPOSER_ROLE(),  address(governor));
        timelock.grantRole(timelock.CANCELLER_ROLE(), address(governor));

        // market: grant minter role to market so it can mint YES/NO shares
        outcomeToken.grantRole(outcomeToken.MINTER_ROLE(), address(market));

        // market: grant minter role to factory markets 
        outcomeToken.grantRole(outcomeToken.MINTER_ROLE(), address(factory));

        // market: transfer default admin role to timelock
        market.grantRole(market.DEFAULT_ADMIN_ROLE(), address(timelock));
        market.revokeRole(market.DEFAULT_ADMIN_ROLE(), deployer);

        // timelock: renounce deployer admin —> timelock is now self-governed
        timelock.renounceRole(timelock.DEFAULT_ADMIN_ROLE(), deployer);

        vm.stopBroadcast();

        // print summary
        console.log("deployment summary");
        console.log("CollateralToken: ", address(collateral));
        console.log("OutcomeToken:    ", address(outcomeToken));
        console.log("FeeVault:        ", address(feeVault));
        console.log("PredictionMarket:", address(market));
        console.log("MarketFactory:   ", address(factory));
        console.log("CPMM:            ", address(cpmm));
        console.log("GovernanceToken: ", address(govToken));
        console.log("MarketTimelock:  ", address(timelock));
        console.log("MarketGovernor:  ", address(governor));
    }
}
