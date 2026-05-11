// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

// mock usdc for testnet and tests (only deploy)
// tests: anyone can mint
// on testnet: owner mints to funded wallets
contract CollateralToken is ERC20, Ownable {

    uint8 private _decimals;

    constructor(string memory name, string memory symbol, uint8 decimals_)
        ERC20(name, symbol)
        Ownable(msg.sender)
    {
        _decimals = decimals_;
    }

    function decimals() public view override returns (uint8) {
        return _decimals;
    }

    // testnet: owner mints on 
    // tests: anyone can call (owner is test contract)
    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
    }
}
