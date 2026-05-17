# Coverage Report

**Project:** On-Chain Prediction Market  
**Date:** May 2026  
**Command:** `forge coverage --no-match-path "test/fork/*" --report summary`

---

## Summary

| File | % Lines | % Statements | % Branches | % Functions |
|---|---|---|---|---|
| `contracts/core/PredictionMarket.sol` | 94.2% | 93.8% | 87.5% | 100% |
| `contracts/core/PredictionMarketV2.sol` | 88.0% | 86.4% | 80.0% | 90.0% |
| `contracts/core/CPMM.sol` | 92.1% | 91.5% | 85.0% | 100% |
| `contracts/core/FeeVault.sol` | 100% | 100% | 100% | 100% |
| `contracts/core/MarketFactory.sol` | 82.4% | 80.0% | 75.0% | 85.7% |
| `contracts/oracles/OracleAdapter.sol` | 90.0% | 88.9% | 83.3% | 100% |
| `contracts/tokens/OutcomeToken.sol` | 95.0% | 94.1% | 90.0% | 100% |
| `contracts/tokens/CollateralToken.sol` | 100% | 100% | 100% | 100% |
| `contracts/governance/PredictionToken.sol` | 85.0% | 83.3% | 80.0% | 90.0% |
| `contracts/governance/MarketGovernor.sol` | 88.0% | 86.7% | 78.6% | 92.3% |
| `contracts/governance/MarketTimelock.sol` | 100% | 100% | 100% | 100% |
| `contracts/utils/YulHelpers.sol` | 100% | 100% | 100% | 100% |
| **Total** | **91.5%** | **90.8%** | **84.9%** | **96.5%** |

**Overall line coverage: 91.5% ≥ 90% requirement ✅**

---

## How to Reproduce

```bash
forge coverage --no-match-path "test/fork/*" --report summary
```

Fork tests are excluded because they require a live RPC endpoint. All other tests run in the local EVM.

---

## Uncovered Lines

### PredictionMarket.sol
- `settleDispute()` edge case when market is already Final — not reachable by design
- Admin setter zero-address checks — partially covered by revert tests

### MarketFactory.sol
- `predictAddress()` — view function, not covered by unit tests
- `deployMarketCreate2()` — covered partially (CREATE2 path)

### MarketGovernor.sol
- Internal override functions (`_cancel`, `_executor`) — called indirectly through Governor
- Some quorum edge cases with zero supply

---

## Notes

- Fork tests (`test/fork/Fork.t.sol`) are excluded from coverage as they require a mainnet RPC
- Coverage is measured on the local EVM with Foundry's built-in coverage tool
- Governance E2E tests (`test/integration/GovernanceE2E.t.sol`) significantly improve Governor coverage