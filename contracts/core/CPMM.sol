// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC1155} from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import {IERC1155Receiver} from "@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol";

//constant-product AMM for outcome shares
// x*y = k, with 0.3% fee
contract CPMM is ReentrancyGuard, IERC1155Receiver {
    //constants
    uint256 private constant FEE_NUMERATOR = 997; // 0.3% fee -> multiply input by 997/1000
    uint256 private constant FEE_DENOMINATOR = 1000;
    uint256 private constant MINIMUM_LIQUIDITY = 1000; // locked forever to prevent div/0

    uint256 private constant YES = 0; // ERC-1155 token id for YES shares
    uint256 private constant NO = 1; // ERC-1155 token id for NO  shares

    //state
    IERC1155 public immutable outcomeToken;

    uint256 public reserveYes;
    uint256 public reserveNo;
    uint256 public totalLpSupply;

    mapping(address => uint256) public lpBalance;

    //events
    event LiquidityAdded(address indexed provider, uint256 amountYes, uint256 amountNo, uint256 lpMinted);
    event LiquidityRemoved(address indexed provider, uint256 amountYes, uint256 amountNo, uint256 lpBurned);
    event Swap(address indexed trader, bool yesForNo, uint256 amountIn, uint256 amountOut);

    //constructor
    constructor(address outcomeToken_) {
        require(outcomeToken_ != address(0), "CPMM: zero token");
        outcomeToken = IERC1155(outcomeToken_);
    }

    function addLiquidity(uint256 yesIn, uint256 noIn, uint256 minLp) external nonReentrant returns (uint256 lpMinted) {
        // Checks
        require(yesIn > 0 && noIn > 0, "CPMM: zero input");

        uint256 _totalLp = totalLpSupply;
        uint256 _resYes = reserveYes;
        uint256 _resNo = reserveNo;

        if (_totalLp == 0) {
            // first deposit: geometric mean minus MINIMUM_LIQUIDITY (locked to address(1))
            lpMinted = _sqrt(yesIn * noIn) - MINIMUM_LIQUIDITY;
            require(lpMinted > 0, "CPMM: insufficient first liquidity");

            // lock MINIMUM_LIQUIDITY permanently
            lpBalance[address(1)] += MINIMUM_LIQUIDITY;
            totalLpSupply = MINIMUM_LIQUIDITY;
        } else {
            // subsequent deposits: LP = min(yesIn/resYes, noIn/resNo) * totalLp
            uint256 lpFromYes = (yesIn * _totalLp) / _resYes;
            uint256 lpFromNo = (noIn * _totalLp) / _resNo;
            lpMinted = lpFromYes < lpFromNo ? lpFromYes : lpFromNo;
        }

        require(lpMinted >= minLp, "CPMM: slippage");

        // effects
        reserveYes = _resYes + yesIn;
        reserveNo = _resNo + noIn;
        totalLpSupply += lpMinted;
        lpBalance[msg.sender] += lpMinted;

        // interactions — pull both tokens in one batch call
        uint256[] memory ids = new uint256[](2);
        uint256[] memory amounts = new uint256[](2);
        ids[0] = YES;
        amounts[0] = yesIn;
        ids[1] = NO;
        amounts[1] = noIn;
        outcomeToken.safeBatchTransferFrom(msg.sender, address(this), ids, amounts, "");

        emit LiquidityAdded(msg.sender, yesIn, noIn, lpMinted);
    }

    function removeLiquidity(uint256 lpAmount, uint256 minYes, uint256 minNo) external nonReentrant {
        // checks
        require(lpAmount > 0, "CPMM: zero lp");
        require(lpBalance[msg.sender] >= lpAmount, "CPMM: insufficient lp");

        uint256 _totalLp = totalLpSupply;
        uint256 _resYes = reserveYes;
        uint256 _resNo = reserveNo;

        uint256 yesOut = (lpAmount * _resYes) / _totalLp;
        uint256 noOut = (lpAmount * _resNo) / _totalLp;

        require(yesOut >= minYes, "CPMM: slippage yes");
        require(noOut >= minNo, "CPMM: slippage no");
        require(yesOut > 0 && noOut > 0, "CPMM: zero output");

        // effects
        lpBalance[msg.sender] -= lpAmount;
        totalLpSupply -= lpAmount;
        reserveYes = _resYes - yesOut;
        reserveNo = _resNo - noOut;

        // interactions — push both tokens in one batch call
        uint256[] memory ids = new uint256[](2);
        uint256[] memory amounts = new uint256[](2);
        ids[0] = YES;
        amounts[0] = yesOut;
        ids[1] = NO;
        amounts[1] = noOut;
        outcomeToken.safeBatchTransferFrom(address(this), msg.sender, ids, amounts, "");

        emit LiquidityRemoved(msg.sender, yesOut, noOut, lpAmount);
    }

    function swap(bool yesForNo, uint256 amountIn, uint256 minOut) external nonReentrant returns (uint256 amountOut) {
        // checks
        require(amountIn > 0, "CPMM: zero input");
        require(reserveYes > 0 && reserveNo > 0, "CPMM: no liquidity");

        uint256 resIn = yesForNo ? reserveYes : reserveNo;
        uint256 resOut = yesForNo ? reserveNo : reserveYes;

        // Core math in Yul — same formula as YulHelpers.amountOutYul but with fee
        amountOut = _getAmountOutYul(amountIn, resIn, resOut);

        require(amountOut >= minOut, "CPMM: slippage");
        require(amountOut < resOut, "CPMM: insufficient liquidity");

        // effects — update reserves before any token transfer (CEI)
        if (yesForNo) {
            reserveYes += amountIn;
            reserveNo -= amountOut;
        } else {
            reserveNo += amountIn;
            reserveYes -= amountOut;
        }

        uint256 tokenIn = yesForNo ? YES : NO;
        uint256 tokenOut = yesForNo ? NO : YES;

        // interactions — pull input, then push output
        outcomeToken.safeTransferFrom(msg.sender, address(this), tokenIn, amountIn, "");
        outcomeToken.safeTransferFrom(address(this), msg.sender, tokenOut, amountOut, "");

        emit Swap(msg.sender, yesForNo, amountIn, amountOut);
    }

    function getAmountOut(bool yesForNo, uint256 amountIn) external view returns (uint256) {
        require(amountIn > 0, "CPMM: zero input");
        require(reserveYes > 0 && reserveNo > 0, "CPMM: no liquidity");

        uint256 resIn = yesForNo ? reserveYes : reserveNo;
        uint256 resOut = yesForNo ? reserveNo : reserveYes;
        return _getAmountOutYul(amountIn, resIn, resOut);
    }

    function impliedProbabilityYes() external view returns (uint256) {
        uint256 total = reserveYes + reserveNo;
        if (total == 0) return 0;
        return (reserveNo * 1e18) / total;
    }

    //internal math functions
    function _getAmountOutYul(uint256 amountIn, uint256 resIn, uint256 resOut) internal pure returns (uint256 out) {
        assembly {
            let amountInWithFee := mul(amountIn, 997)
            let numerator := mul(amountInWithFee, resOut)
            let denominator := add(mul(resIn, 1000), amountInWithFee)
            out := div(numerator, denominator)
        }
    }

    function _getAmountOutSolidity(uint256 amountIn, uint256 resIn, uint256 resOut) internal pure returns (uint256) {
        uint256 amountInWithFee = amountIn * 997;
        return (amountInWithFee * resOut) / (resIn * 1000 + amountInWithFee);
    }

    function _sqrt(uint256 y) internal pure returns (uint256 z) {
        if (y > 3) {
            z = y;
            uint256 x = y / 2 + 1;
            while (x < z) {
                z = x;
                x = (y / x + x) / 2;
            }
        } else if (y != 0) {
            z = 1;
        }
    }

    //ERC-1155 receiver functions
    // Required so the contract can hold ERC-1155 tokens
    function onERC1155Received(address, address, uint256, uint256, bytes calldata)
        external
        pure
        override
        returns (bytes4)
    {
        return this.onERC1155Received.selector;
    }

    function onERC1155BatchReceived(address, address, uint256[] calldata, uint256[] calldata, bytes calldata)
        external
        pure
        override
        returns (bytes4)
    {
        return this.onERC1155BatchReceived.selector;
    }

    function supportsInterface(bytes4 interfaceId) external pure override returns (bool) {
        return interfaceId == type(IERC1155Receiver).interfaceId;
    }
}
