// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";

contract GovernanceToken is ERC20, ERC20Permit, ERC20Votes {
    uint256 public constant TOTAL_SUPPLY = 1_000_000 ether;

    constructor(address team, address treasury, address community, address liquidity)
        ERC20("GovToken", "GOV")
        ERC20Permit("GovToken")
    {
        _mint(team,      400_000 ether); // 40%
        _mint(treasury,  300_000 ether); // 30%
        _mint(community, 200_000 ether); // 20%
        _mint(liquidity, 100_000 ether); // 10%
    }

    // overrides
    function _update(address from, address to, uint256 amount)
        internal override(ERC20, ERC20Votes) {
        super._update(from, to, amount);
    }

    function nonces(address owner)
        public view override(ERC20Permit, Nonces) returns (uint256) {
        return super.nonces(owner);
    }
}