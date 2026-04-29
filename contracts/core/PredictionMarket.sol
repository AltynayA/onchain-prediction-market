// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

// Core market contract — UUPS upgradeable
contract PredictionMarket is UUPSUpgradeable, AccessControlUpgradeable, ReentrancyGuard {
    bytes32 public constant RESOLVER_ROLE = keccak256("RESOLVER_ROLE");

    enum MarketState {
        Active,
        Resolved,
        Disputed
    }

    struct Market {
        string question;
        uint256 resolutionTime;
        MarketState state;
        bool outcome; // true = YES won
    }

    mapping(uint256 => Market) public markets;
    uint256 public marketCount;

    event MarketCreated(uint256 indexed marketId, string question, uint256 resolutionTime);
    event MarketResolved(uint256 indexed marketId, bool outcome);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address admin) public initializer {
        __AccessControl_init();
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
    }

    // TODO: createMarket()
    // TODO: buyShares()
    // TODO: resolveMarket()
    // TODO: redeemShares()

    function _authorizeUpgrade(address) internal override onlyRole(DEFAULT_ADMIN_ROLE) {}
}
