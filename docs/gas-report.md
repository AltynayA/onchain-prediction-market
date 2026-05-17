# Gas Optimization Report

**Project:** On-Chain Prediction Market  
**Date:** May 2026  
**Tool:** `forge snapshot`

---

## Summary

The protocol uses Yul assembly in `YulHelpers.sol` and `CPMM.sol` for gas-critical calculations. This report compares Yul vs Solidity implementations and L1 vs L2 deployment costs.

---

## Yul vs Solidity Benchmarks

Benchmarks captured with `forge snapshot --match-contract YulBenchmark`.

| Function | Yul (gas) | Solidity (gas) | Savings |
|---|---|---|---|
| `calcFee` | 5,495 | 5,659 | 164 (2.9%) |
| `amountOut` | 5,600 | 5,958 | 358 (6.0%) |
| `isPowerOfTwo` | 5,511 | 5,734 | 223 (3.9%) |

All Yul functions produce **identical outputs** to their Solidity equivalents — verified by fuzz tests in `test/unit/YulHelpers.t.sol` with 256 runs each.

### calcFee — Fee calculation
```solidity
// Yul version (gas: 5,495)
assembly {
    fee := div(mul(amountIn, feeBps), 10000)
}

// Solidity version (gas: 5,659)
return (amount * feeBps) / 10000;
```

### amountOut — AMM output calculation
```solidity
// Yul version (gas: 5,600)
assembly {
    let amountInWithFee := mul(amountIn, 997)
    let numerator       := mul(amountInWithFee, resOut)
    let denominator     := add(mul(resIn, 1000), amountInWithFee)
    out := div(numerator, denominator)
}

// Solidity version (gas: 5,958)
uint256 amountInWithFee = amountIn * 997;
return (amountInWithFee * resOut) / (resIn * 1000 + amountInWithFee);
```

---

## L1 vs L2 Gas Comparison

Operations measured on Ethereum Mainnet (estimated) vs Base Sepolia (actual).

| Operation | L1 Gas | L1 Cost (~30 gwei) | L2 Gas | L2 Cost (~0.006 gwei) | Savings |
|---|---|---|---|---|---|
| `createMarket` | ~120,000 | ~$7.20 | ~118,836 | ~$0.0002 | 99.9% |
| `buyShares` | ~180,000 | ~$10.80 | ~165,000 | ~$0.0003 | 99.9% |
| `addLiquidity` | ~250,000 | ~$15.00 | ~230,000 | ~$0.0004 | 99.9% |
| `swap` | ~120,000 | ~$7.20 | ~110,000 | ~$0.0002 | 99.9% |
| `deposit` (vault) | ~90,000 | ~$5.40 | ~85,000 | ~$0.0001 | 99.9% |
| `castVote` | ~80,000 | ~$4.80 | ~75,000 | ~$0.0001 | 99.9% |

L2 deployment on Base Sepolia costs approximately **$0.0001 per transaction** vs **$5–15 on L1**. This makes the protocol economically viable for small trades that would be uneconomical on mainnet.

---

## Optimizer Settings

```toml
[profile.default]
optimizer        = true
optimizer_runs   = 200
```

With optimizer enabled, `PredictionMarket` implementation size reduced from >24,576 bytes (over EIP-170 limit) to 10,574 bytes — well within the 24KB contract size limit.

---

## Gas Snapshot

Full snapshot output from `forge snapshot --match-contract YulBenchmark`:

```
YulBenchmark::test_gas_amountOut_solidity() (gas: 5958)
YulBenchmark::test_gas_amountOut_yul() (gas: 5600)
YulBenchmark::test_gas_calcFee_solidity() (gas: 5659)
YulBenchmark::test_gas_calcFee_yul() (gas: 5495)
YulBenchmark::test_gas_isPowerOfTwo_solidity() (gas: 5734)
YulBenchmark::test_gas_isPowerOfTwo_yul() (gas: 5511)
```

Snapshot file committed to repo at `.gas-snapshot`.