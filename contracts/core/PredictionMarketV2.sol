pragma solidity ^0.8.24;

import {PredictionMarket} from "./PredictionMarket.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract PredictionMarketV2 is PredictionMarket {
    using SafeERC20 for IERC20;

    //new V2 storage (uses V1 __gap slots 12-13)
    address public emergencyRecipient;
    mapping(uint256 => uint256) public marketFeeBps; // 0 = use global FEE_BPS

    //events
    event EmergencyWithdrawal(uint256 indexed marketId, address indexed recipient, uint256 amount);
    event MarketFeeSet(uint256 indexed marketId, uint256 feeBps);
    event EmergencyRecipientSet(address indexed recipient);

    //V2 initializer
    function initializeV2(address recipient_) external onlyRole(DEFAULT_ADMIN_ROLE) reinitializer(2) {
        require(recipient_ != address(0), "V2: zero recipient");
        emergencyRecipient = recipient_;
    }

    //new V2 functions
    function emergencyWithdraw(uint256 marketId) external onlyRole(DEFAULT_ADMIN_ROLE) nonReentrant {
        // checks
        Market storage m = markets[marketId];
        require(m.state == MarketState.Disputed, "V2: not disputed");
        require(emergencyRecipient != address(0), "V2: no recipient set");

        uint256 amount = m.totalCollateral;
        require(amount > 0, "V2: nothing to withdraw");

        // effects
        m.totalCollateral = 0;
        m.state = MarketState.Final;

        // interactions
        collateral.safeTransfer(emergencyRecipient, amount);

        emit EmergencyWithdrawal(marketId, emergencyRecipient, amount);
    }

    function setMarketFee(uint256 marketId, uint256 feeBps_) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(feeBps_ <= 1000, "V2: fee too high"); // max 10%
        require(marketId < marketCount, "V2: invalid market");
        marketFeeBps[marketId] = feeBps_;
        emit MarketFeeSet(marketId, feeBps_);
    }

    // returns market fee or global fee
    function effectiveFee(uint256 marketId) public view returns (uint256) {
        uint256 override_ = marketFeeBps[marketId];
        return override_ > 0 ? override_ : FEE_BPS;
    }

    //update the emergency recipient address
    function setEmergencyRecipient(address recipient_) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(recipient_ != address(0), "V2: zero recipient");
        emergencyRecipient = recipient_;
        emit EmergencyRecipientSet(recipient_);
    }

    // storage gap so v2 and v3 releases don't collide
    uint256[42] private __gapV2;
}
