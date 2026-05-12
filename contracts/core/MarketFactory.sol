// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {PredictionMarket} from "./PredictionMarket.sol";

// deploys new prediction market instances using create and create2
contract MarketFactory is AccessControl {
    bytes32 public constant FACTORY_ADMIN = keccak256("FACTORY_ADMIN");

    // shared logic contract — all proxies point here
    address public immutable implementation;

    // shared dependencies passed to every deployed market
    address public collateral;
    address public outcomeToken;
    address public feeVault;
    uint256 public defaultStaleness;
    uint256 public defaultDisputeWindow;

    // registry
    address[] public allMarkets;
    mapping(address => bool) public isMarket;

    event MarketDeployed(
        address indexed market,
        address indexed admin,
        bytes32 salt,
        bool usedCreate2
    );

    constructor(
        address admin_,
        address collateral_,
        address outcomeToken_,
        address feeVault_,
        uint256 staleness_,
        uint256 disputeWindow_
    ) {
        require(admin_ != address(0), "MF: zero admin");
        require(collateral_ != address(0), "MF: zero collateral");
        require(outcomeToken_ != address(0), "MF: zero outcomeToken");
        require(feeVault_ != address(0), "MF: zero feeVault");

        _grantRole(DEFAULT_ADMIN_ROLE, admin_);
        _grantRole(FACTORY_ADMIN, admin_);

        // deploy the shared implementation once
        implementation = address(new PredictionMarket());

        collateral = collateral_;
        outcomeToken = outcomeToken_;
        feeVault = feeVault_;
        defaultStaleness = staleness_;
        defaultDisputeWindow = disputeWindow_;
    }

    // deploy with create -> nonce based address
    function deployMarket(
        address marketAdmin
    ) external onlyRole(FACTORY_ADMIN) returns (address market) {
        require(marketAdmin != address(0), "MF: zero market admin");

        ERC1967Proxy proxy = new ERC1967Proxy(
            implementation,
            _initData(marketAdmin)
        );
        market = address(proxy);
        _register(market);

        emit MarketDeployed(market, marketAdmin, bytes32(0), false);
    }

    // deploy with create2 —> deterministic address from salt
    function deployMarketCreate2(
        address marketAdmin,
        bytes32 salt
    ) external onlyRole(FACTORY_ADMIN) returns (address market) {
        require(marketAdmin != address(0), "MF: zero market admin");

        // XOR salt with admin address to prevent front-running
        bytes32 effectiveSalt = salt ^ bytes32(uint256(uint160(marketAdmin)));
        ERC1967Proxy proxy = new ERC1967Proxy{salt: effectiveSalt}(
            implementation,
            _initData(marketAdmin)
        );
        market = address(proxy);
        _register(market);
        emit MarketDeployed(market, marketAdmin, salt, true);
    }

    // predict the address (pre-approvals)
    function predictAddress(
        address marketAdmin,
        bytes32 salt
    ) external view returns (address) {
        bytes32 effectiveSalt = salt ^ bytes32(uint256(uint160(marketAdmin)));
        bytes memory initCode = abi.encodePacked(
            type(ERC1967Proxy).creationCode,
            abi.encode(implementation, _initData(marketAdmin))
        );
        return
            address(
                uint160(
                    uint256(
                        keccak256(
                            abi.encodePacked(
                                bytes1(0xff),
                                address(this),
                                effectiveSalt,
                                keccak256(initCode)
                            )
                        )
                    )
                )
            );
    }

    // admin setters
    function setFeeVault(address v) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(v != address(0));
        feeVault = v;
    }
    function setStaleness(uint256 s) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(s > 0);
        defaultStaleness = s;
    }
    function setDisputeWindow(uint256 w) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(w > 0);
        defaultDisputeWindow = w;
    }

    function allMarketsLength() external view returns (uint256) {
        return allMarkets.length;
    }

    //internal
    function _initData(
        address marketAdmin
    ) internal view returns (bytes memory) {
        return
            abi.encodeCall(
                PredictionMarket.initialize,
                (
                    marketAdmin,
                    collateral,
                    outcomeToken,
                    defaultStaleness,
                    defaultDisputeWindow,
                    feeVault
                )
            );
    }

    function _register(address market) internal {
        allMarkets.push(market);
        isMarket[market] = true;
    }
}
