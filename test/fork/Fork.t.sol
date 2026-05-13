// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {OracleAdapter} from "../../contracts/oracles/OracleAdapter.sol";
import {FeeVault} from "../../contracts/core/FeeVault.sol";
import {PredictionMarket} from "../../contracts/core/PredictionMarket.sol";
import {OutcomeToken} from "../../contracts/tokens/OutcomeToken.sol";

// forks ethereum mainnet and interacts with real deployed protocols
// run with: source .env && forge test --match-path test/fork/Fork.t.sol --fork-url $MAINNET_RPC_URL -vvv
contract ForkTest is Test {

    // erc-1155 receiver hooks so this contract can hold outcome tokens
    function onERC1155Received(address, address, uint256, uint256, bytes calldata)
        external pure returns (bytes4)
    {
        return this.onERC1155Received.selector;
    }

    function onERC1155BatchReceived(address, address, uint256[] calldata, uint256[] calldata, bytes calldata)
        external pure returns (bytes4)
    {
        return this.onERC1155BatchReceived.selector;
    }


    // mainnet addresses
    address constant USDC         = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant CHAINLINK_ETH = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419;
    address constant USDC_WHALE   = 0x37305B1cD40574E4C5Ce33f8e8306Be057fD7341;

    // actors
    address admin    = makeAddr("admin");
    address resolver = makeAddr("resolver");

    uint256 mainnetFork;

    function setUp() public {
        mainnetFork = vm.createFork(vm.envString("MAINNET_RPC_URL"));
        vm.selectFork(mainnetFork);
    }

    // 1 wrap real chainlink feed in oracleadapter and verify price
    function test_fork_oracleAdapter_realChainlinkFeed() public {
        OracleAdapter adapter = new OracleAdapter(CHAINLINK_ETH);

        int256 price = adapter.getPrice();
        assertGt(price, 100e8, "ETH price should be > $100");

        // generous staleness window for fork latency
        adapter.assertFresh(3 hours);
    }

    // 2 deposit and redeem roundtrip with real usdc
    function test_fork_feeVault_depositAndRedeem_withRealUSDC() public {
        FeeVault vault = new FeeVault(IERC20(USDC));
        assertEq(vault.asset(), USDC);

        uint256 amount = 1000e6;

        // fund from whale
        vm.prank(USDC_WHALE);
        IERC20(USDC).transfer(address(this), amount);

        // deposit
        IERC20(USDC).approve(address(vault), type(uint256).max);
        uint256 shares = vault.deposit(amount, address(this));

        assertGt(shares, 0);
        assertEq(vault.totalAssets(), amount);
        assertEq(vault.balanceOf(address(this)), shares);

        // redeem
        uint256 assetsOut = vault.redeem(shares, address(this), address(this));

        assertLe(assetsOut, amount);
        assertApproxEqAbs(assetsOut, amount, 1);
    }

    // 3 fees sent to vault accumulate correctly
    function test_fork_feeVault_accumulatesFees_withRealUSDC() public {
        FeeVault vault = new FeeVault(IERC20(USDC));

        uint256 feeAmount = 10e6;

        vm.prank(USDC_WHALE);
        IERC20(USDC).transfer(address(vault), feeAmount);

        assertEq(vault.totalAssets(), feeAmount);
        assertEq(IERC20(USDC).balanceOf(address(vault)), feeAmount);
    }

    // 4 prediction market buyshares end-to-end with real usdc
    function test_fork_predictionMarket_buyShares_withRealUSDC() public {
        OutcomeToken  outcomeToken = new OutcomeToken();
        FeeVault      feeVault     = new FeeVault(IERC20(USDC));
        OracleAdapter oracle       = new OracleAdapter(CHAINLINK_ETH);

        PredictionMarket impl = new PredictionMarket();
        PredictionMarket market = PredictionMarket(address(new ERC1967Proxy(
            address(impl),
            abi.encodeCall(PredictionMarket.initialize, (
                admin,
                USDC,
                address(outcomeToken),
                3 hours,
                2 days,
                address(feeVault)
            ))
        )));

        outcomeToken.grantRole(outcomeToken.MINTER_ROLE(), address(market));

        vm.startPrank(admin);
        market.grantRole(market.RESOLVER_ROLE(), resolver);
        uint256 marketId = market.createMarket(
            "Will ETH > $5000 by end of 2025?",
            block.timestamp + 30 days,
            address(oracle)
        );
        vm.stopPrank();

        // fund address(this) with real usdc
        uint256 amount = 1000e6;
        vm.prank(USDC_WHALE);
        IERC20(USDC).transfer(address(this), amount);

        // buy yes shares as address(this) —> test contract handles erc-1155 callbacks
        IERC20(USDC).approve(address(market), type(uint256).max);
        market.buyShares(marketId, true, amount, 0);

        uint256 expectedFee = (amount * 100) / 10000;
        uint256 expectedNet = amount - expectedFee;

        assertEq(IERC20(USDC).balanceOf(address(feeVault)), expectedFee);
        assertEq(IERC20(USDC).balanceOf(address(market)),   expectedNet);
        assertEq(outcomeToken.balanceOf(address(this), 0),  expectedNet);
    }
}
