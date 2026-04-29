// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

//constant-product AMM for outcome shares
// x*y = k, with 0.3% fee
contract CPMM {
    uint256 public reserveYes;
    uint256 public reserveNo;
    uint256 public totalLpSupply;

    mapping(address => uint256) public lpBalance;

    uint256 private constant FEE_NUMERATOR = 997;
    uint256 private constant FEE_DENOMINATOR = 1000;

    event LiquidityAdded(address indexed provider, uint256 amountYes, uint256 amountNo, uint256 lpMinted);
    event LiquidityRemoved(address indexed provider, uint256 amountYes, uint256 amountNo, uint256 lpBurned);
    event Swap(address indexed trader, bool yesForNo, uint256 amountIn, uint256 amountOut);

    // TODO: implement addLiquidity()
    // TODO: implement removeLiquidity()
    // TODO: implement swap()
    // TODO: implement getAmountOut()
}
