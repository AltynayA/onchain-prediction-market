// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {PredictionMarket} from "./core/PredictionMarket.sol";

// deploys new prediction market instances using create and create2
contract MarketFactory is AccessControl {

    bytes32 public constant FACTORY_ADMIN = keccak256("FACTORY_ADMIN");

    // shared dependencies passed to every deployed market
    address public collateral;
    address public outcomeToken;
    uint256 public defaultStaleness;
    uint256 public defaultDisputeWindow;

    // registry
    address[] public allMarkets;
    mapping(address => bool) public isMarket;

    event MarketDeployed(address indexed market, bytes32 salt, bool usedCreate2);

    constructor(
        address admin,
        address _collateral,
        address _outcomeToken,
        uint256 _staleness,
        uint256 _disputeWindow
    ) {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(FACTORY_ADMIN, admin);

        collateral           = _collateral;
        outcomeToken         = _outcomeToken;
        defaultStaleness     = _staleness;
        defaultDisputeWindow = _disputeWindow;
    }

    // deploy with create -> nonce based address
    function deployMarket(address admin) external onlyRole(FACTORY_ADMIN) returns (address market) {
        PredictionMarket m = new PredictionMarket();
        m.initialize(admin, collateral, outcomeToken, defaultStaleness, defaultDisputeWindow);

        market = address(m);
        allMarkets.push(market);
        isMarket[market] = true;

        emit MarketDeployed(market, bytes32(0), false);
    }

    // deploy with create2 —> deterministic address from salt
    function deployMarketCreate2(address admin, bytes32 salt)
        external
        onlyRole(FACTORY_ADMIN)
        returns (address market)
    {
        PredictionMarket m = new PredictionMarket{salt: salt}();
        m.initialize(admin, collateral, outcomeToken, defaultStaleness, defaultDisputeWindow);

        market = address(m);
        allMarkets.push(market);
        isMarket[market] = true;

        emit MarketDeployed(market, salt, true);
    }

    // predict the address (pre-approvals)
    function predictAddress(bytes32 salt) external view returns (address) {
        bytes32 hash = keccak256(
            abi.encodePacked(
                bytes1(0xff),
                address(this),
                salt,
                keccak256(type(PredictionMarket).creationCode)
            )
        );
        return address(uint160(uint256(hash)));
    }

    function allMarketsLength() external view returns (uint256) {
        return allMarkets.length;
    }
}
