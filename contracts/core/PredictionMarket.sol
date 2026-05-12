// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IOutcomeToken {
    function mint(address to, uint256 id, uint256 amount) external;
    function burn(address from, uint256 id, uint256 amount) external;
}

interface IOracleAdapter {
    function assertFresh(uint256 maxAge) external view;
}

// Core market contract — UUPS upgradeable
contract PredictionMarket is
    UUPSUpgradeable,
    AccessControlUpgradeable,
    PausableUpgradeable,
    ReentrancyGuard
{
    using SafeERC20 for IERC20;

    //roles
    bytes32 public constant RESOLVER_ROLE = keccak256("RESOLVER_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    //state
    enum MarketState {
        Active,
        Pending,
        Disputed,
        Final
    }

    struct Market {
        string question;
        uint256 resolutionTime;
        uint256 disputeDeadline;
        uint256 totalCollateral;
        uint256 yesShares;
        uint256 noShares;
        MarketState state;
        bool outcome;
        address oracleAdapter;
    }

    mapping(uint256 => Market) public markets;
    uint256 public marketCount;

    IERC20 public collateral;
    IOutcomeToken public outcomeToken;
    uint256 public defaultStaleness;
    uint256 public defaultDisputeWindow;
    address public feeVault;

    uint256 public constant FEE_BPS = 100; // 1%

    //events
    event MarketCreated(uint256 indexed marketId, string question, uint256 resolutionTime, address oracleAdapter);
    event SharesBought(uint256 indexed marketId, address indexed buyer, bool isYes, uint256 collateralIn, uint256 sharesMinted);
    event MarketResolved(uint256 indexed marketId, bool outcome, uint256 disputeDeadline);
    event MarketDisputed(uint256 indexed marketId, address indexed disputer);
    event MarketFinalized(uint256 indexed marketId, bool outcome);
    event SharesRedeemed(uint256 indexed marketId, address indexed redeemer, uint256 sharesIn, uint256 collateralOut);

    //constructor/initializer
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address admin_,
        address collateral_,
        address outcomeToken_,
        uint256 staleness_,
        uint256 disputeWindow_,
        address feeVault_
    ) public initializer {
        __AccessControl_init();
        __Pausable_init();

        require(admin_ != address(0), "PM: zero admin");
        require(collateral_ != address(0), "PM: zero collateral");
        require(outcomeToken_ != address(0), "PM: zero outcomeToken");
        require(feeVault_ != address(0), "PM: zero feeVault");
        require(staleness_ > 0, "PM: zero staleness");
        require(disputeWindow_ > 0, "PM: zero dispute window");

        _grantRole(DEFAULT_ADMIN_ROLE, admin_);
        _grantRole(RESOLVER_ROLE, admin_);
        _grantRole(PAUSER_ROLE, admin_);

        collateral = IERC20(collateral_);
        outcomeToken = IOutcomeToken(outcomeToken_);
        defaultStaleness = staleness_;
        defaultDisputeWindow = disputeWindow_;
        feeVault = feeVault_;
    }

    //market lifecycle
    function createMarket(
        string calldata question_,
        uint256 resolutionTime_,
        address oracleAdapter_
    )
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
        whenNotPaused
        returns (uint256 marketId)
    {
        require(bytes(question_).length > 0, "PM: empty question");
        require(resolutionTime_ > block.timestamp, "PM: resolution in past");
        require(oracleAdapter_ != address(0), "PM: zero oracle");

        marketId = marketCount++;
        Market storage m = markets[marketId];
        m.question = question_;
        m.resolutionTime = resolutionTime_;
        m.oracleAdapter = oracleAdapter_;
        m.state = MarketState.Active;

        emit MarketCreated(
            marketId,
            question_,
            resolutionTime_,
            oracleAdapter_
        );
    }

    function buyShares(
        uint256 marketId,
        bool isYes,
        uint256 amountIn,
        uint256 minShares
    ) external nonReentrant whenNotPaused {
        // Checks
        Market storage m = markets[marketId];
        require(m.state == MarketState.Active, "PM: market not active");
        require(block.timestamp < m.resolutionTime, "PM: past resolution time");
        require(amountIn > 0, "PM: zero amount");

        // fee in Yul (benchmarked in YulHelpers.calcFeeYul)
        uint256 fee;
        assembly {
            fee := div(mul(amountIn, 100), 10000)
        }
        uint256 netAmount = amountIn - fee;
        require(netAmount >= minShares, "PM: slippage");

        // effects — all state updated before any external call (CEI)
        m.totalCollateral += amountIn;
        if (isYes) {
            m.yesShares += netAmount;
        } else {
            m.noShares += netAmount;
        }

        // Interactions
        collateral.safeTransferFrom(msg.sender, address(this), amountIn);
        if (fee > 0) collateral.safeTransfer(feeVault, fee);
        outcomeToken.mint(msg.sender, isYes ? 0 : 1, netAmount);

        emit SharesBought(marketId, msg.sender, isYes, amountIn, netAmount);
    }

    function resolveMarket(
        uint256 marketId,
        bool outcome
    ) external onlyRole(RESOLVER_ROLE) nonReentrant whenNotPaused {
        Market storage m = markets[marketId];
        require(m.state == MarketState.Active, "PM: not active");
        require(block.timestamp >= m.resolutionTime, "PM: too early");

        IOracleAdapter(m.oracleAdapter).assertFresh(defaultStaleness);

        uint256 deadline = block.timestamp + defaultDisputeWindow;
        m.state = MarketState.Pending;
        m.outcome = outcome;
        m.disputeDeadline = deadline;

        emit MarketResolved(marketId, outcome, deadline);
    }

    function disputeMarket(uint256 marketId) external whenNotPaused {
        Market storage m = markets[marketId];
        require(m.state == MarketState.Pending, "PM: not pending");
        require(block.timestamp < m.disputeDeadline, "PM: window expired");

        m.state = MarketState.Disputed;
        emit MarketDisputed(marketId, msg.sender);
    }

    function finalizeMarket(uint256 marketId) external whenNotPaused {
        Market storage m = markets[marketId];
        require(m.state == MarketState.Pending, "PM: not pending");
        require(block.timestamp >= m.disputeDeadline, "PM: window not over");

        m.state = MarketState.Final;
        emit MarketFinalized(marketId, m.outcome);
    }

    function settleDispute(
        uint256 marketId,
        bool forcedOutcome
    ) external onlyRole(DEFAULT_ADMIN_ROLE) whenNotPaused {
        Market storage m = markets[marketId];
        require(m.state == MarketState.Disputed, "PM: not disputed");

        m.outcome = forcedOutcome;
        m.state = MarketState.Final;
        emit MarketFinalized(marketId, forcedOutcome);
    }

    function redeemShares(
        uint256 marketId,
        uint256 amount
    ) external nonReentrant whenNotPaused {
        // checks
        Market storage m = markets[marketId];
        require(m.state == MarketState.Final, "PM: not final");
        require(amount > 0, "PM: zero amount");

        uint256 winningId = m.outcome ? 0 : 1;
        uint256 totalWin = m.outcome ? m.yesShares : m.noShares;
        require(totalWin > 0, "PM: no winning shares");

        uint256 collateralOut = (amount * m.totalCollateral) / totalWin;
        require(collateralOut > 0, "PM: zero payout");

        // effects before interactions (CEI)
        outcomeToken.burn(msg.sender, winningId, amount);
        m.totalCollateral -= collateralOut;

        // interactions
        collateral.safeTransfer(msg.sender, collateralOut);
        emit SharesRedeemed(marketId, msg.sender, amount, collateralOut);
    }

    //circuit breakers
    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }
    function unpause() external onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    //admin setters
    function setFeeVault(address v) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(v != address(0), "PM: zero");
        feeVault = v;
    }
    function setStaleness(uint256 s) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(s > 0, "PM: zero");
        defaultStaleness = s;
    }
    function setDisputeWindow(uint256 w) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(w > 0, "PM: zero");
        defaultDisputeWindow = w;
    }

    function getMarket(uint256 marketId) external view returns (Market memory) {
        return markets[marketId];
    }

    // UUPS upgrade authorization
    function _authorizeUpgrade(
        address
    ) internal override onlyRole(DEFAULT_ADMIN_ROLE) {}

// storage gap for future V1 additions (V2 appends after this)
    uint256[44] private __gap;
}
