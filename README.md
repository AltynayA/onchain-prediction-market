# On-Chain Prediction Market

A decentralized binary-outcome prediction market built on Base Sepolia.
Users buy YES/NO outcome shares, liquidity providers earn fees via an AMM,
and all protocol parameters are governed by a DAO with a 2-day Timelock.

---

## Team

| Member | Role |
|---|---|
| [@Baldauren000](https://github.com/Baldauren000) (also [@Baldauren1](https://github.com/Baldauren1))  | Smart contracts, AMM, tests |
| [@AltynayA](https://github.com/AltynayA) | Governance, deployment, CI/CD, fork tests |
| [@zhaniya-p](https://github.com/zhaniya-p) | Frontend, subgraph, documentation |

---

## Deployed Contracts — Base Sepolia (chain 84532)

| Contract | Address |
|---|---|
| CollateralToken (mUSDC) | [0x8fAC0f9B73DaC33f6d981A58a2De2C9a61A5d50C](https://sepolia.basescan.org/address/0x8fAC0f9B73DaC33f6d981A58a2De2C9a61A5d50C) |
| OutcomeToken (ERC-1155) | [0x8A6A50Db75992c17e9adFde99818921757521B3e](https://sepolia.basescan.org/address/0x8A6A50Db75992c17e9adFde99818921757521B3e) |
| FeeVault (ERC-4626) | [0x89a375715161F7221a890eB7dE11086d9Aa0DE84](https://sepolia.basescan.org/address/0x89a375715161F7221a890eB7dE11086d9Aa0DE84) |
| PredictionMarket (proxy) | [0x0cEC8fd1fD75bFe985807BeEEC1ACdaBE1784bB7](https://sepolia.basescan.org/address/0x0cEC8fd1fD75bFe985807BeEEC1ACdaBE1784bB7) |
| PredictionMarket (impl) | [0x712F373B113ea2C1d8880aF01d388DA7F25F6d9C](https://sepolia.basescan.org/address/0x712F373B113ea2C1d8880aF01d388DA7F25F6d9C) |
| MarketFactory | [0xe81681ffC729181CbcB7943745DB79325136E8DE](https://sepolia.basescan.org/address/0xe81681ffC729181CbcB7943745DB79325136E8DE) |
| CPMM | [0x903FB4d0A0c7FA3a076D900039737B0b059A1d79](https://sepolia.basescan.org/address/0x903FB4d0A0c7FA3a076D900039737B0b059A1d79) |
| GovernanceToken (PRED) | [0xA7086085727494305CD37E13adF446c096B24e70](https://sepolia.basescan.org/address/0xA7086085727494305CD37E13adF446c096B24e70) |
| MarketTimelock | [0xE699943a7d8b351E8c30064dB3511278D5f58042](https://sepolia.basescan.org/address/0xE699943a7d8b351E8c30064dB3511278D5f58042) |
| MarketGovernor | [0xBdF66e0A87a5759444ec0b585BDf581Ce3Ef309E](https://sepolia.basescan.org/address/0xBdF66e0A87a5759444ec0b585BDf581Ce3Ef309E) |

All contracts verified on [Basescan](https://sepolia.basescan.org).

---

## Architecture Overview

```
User
 └─ PredictionMarket (UUPS proxy)
      ├─ OutcomeToken (ERC-1155 YES/NO shares)
      ├─ CollateralToken (ERC-20 mock USDC)
      ├─ FeeVault (ERC-4626, receives 1% fee)
      ├─ OracleAdapter → Chainlink ETH/USD
      └─ MarketFactory (CREATE + CREATE2)

CPMM (x·y=k AMM)
 └─ OutcomeToken

Governance
 └─ MarketGovernor (OZ Governor)
      ├─ GovernanceToken (ERC20Votes + ERC20Permit)
      └─ MarketTimelock (2-day delay)
           └─ controls PredictionMarket admin
```

---

## Design Patterns

| Pattern | Where used |
|---|---|
| UUPS proxy | `PredictionMarket` + `PredictionMarketV2` |
| Factory (CREATE + CREATE2) | `MarketFactory` |
| Checks-Effects-Interactions | `buyShares`, `redeemShares` in `PredictionMarket` |
| ReentrancyGuard | all state-changing functions in `PredictionMarket` and `CPMM` |
| AccessControl / Role-based | `RESOLVER_ROLE`, `PAUSER_ROLE` in `PredictionMarket` |
| Pausable / Circuit Breaker | `PredictionMarket.pause()` / `unpause()` |
| State Machine | `MarketState` enum: Active → Pending → Disputed/Final |
| Oracle adapter / abstraction | `OracleAdapter` wraps Chainlink, called via `IOracleAdapter` |
| Timelock | `MarketTimelock` (2-day delay) controls all governance actions |
| Pull-over-push payments | `redeemShares` — winners pull their collateral |

---

## Setup

### Prerequisites

- [Foundry](https://book.getfoundry.sh/getting-started/installation)
- Git

### Install

```bash
git clone https://github.com/AltynayA/onchain-prediction-market.git
cd onchain-prediction-market
git submodule update --init --recursive
```

### Build

```bash
forge build
```

### Test

```bash
# unit, fuzz, invariant (no RPC needed)
forge test --no-match-path "test/fork/*" -vvv

# fork tests (requires MAINNET_RPC_URL in .env)
source .env
forge test --match-path "test/fork/*" --fork-url $MAINNET_RPC_URL -vvv

# gas benchmarks
forge snapshot --match-contract YulBenchmark
```

### Coverage

```bash
forge coverage --no-match-path "test/fork/*" --report summary
```

---

## Test Suite

| Type        | Count  | Minimum |
|-------------|--------|---------|
| Unit        | 55     | 50      |
| Fuzz        | 10     | 10      |
| Invariant   | 5      | 5       |
| Fork        | 4      | 3       |
| Integration | 6      | —       |
| **Total**   | **80** | 80      |

```
test/unit/PredictionMarket.t.sol     — 46 tests (core market functions)
test/unit/Governance.t.sol           —  9 tests (token, timelock, governor)
test/integration/GovernanceE2E.t.sol —  6 tests (full propose→execute lifecycle)
test/fuzz/Fuzz.t.sol                 — 10 fuzz tests (AMM, fees, Yul)
test/invariant/Invariant.t.sol       —  5 invariants (k, LP supply, collateral)
test/fork/Fork.t.sol                 —  4 fork tests (Chainlink, USDC, market)
```

---

## Environment Variables

Create a `.env` file in the repo root (never commit — already in `.gitignore`):

```dotenv
MAINNET_RPC_URL=https://eth-mainnet.g.alchemy.com/v2/YOUR_KEY
BASE_SEPOLIA_RPC_URL=https://base-sepolia.g.alchemy.com/v2/YOUR_KEY
PRIVATE_KEY=0xYOUR_TESTNET_PRIVATE_KEY_NEVER_USE_MAINNET
BASESCAN_API_KEY=YOUR_BASESCAN_KEY

# Filled automatically after running deploy script
MARKET_ADDRESS=
TIMELOCK_ADDRESS=
GOVERNOR_ADDRESS=
```

---

## Deployment

### Deploy to Base Sepolia

```bash
source .env
forge script script/Deploy.s.sol:Deploy \
  --rpc-url $BASE_SEPOLIA_RPC_URL \
  --private-key $PRIVATE_KEY \
  --broadcast \
  --verify \
  --etherscan-api-key $BASESCAN_API_KEY \
  --slow -vvvv
```

### Post-deployment verification

```bash
source .env
forge script script/Verify.s.sol:Verify \
  --rpc-url $BASE_SEPOLIA_RPC_URL -vvvv
```

Checks: Timelock is market admin, deployer has no admin role,
Timelock delay = 2 days, Governor params match spec.

---

## Frontend

Simple HTML/JS dApp — no framework, no build step required.

Open `frontend/index.html` directly in your browser.

Requires MetaMask on Base Sepolia testnet.

Pages:
- **Dashboard** — wallet info, token balance, voting power, pool reserves
- **Market** — buy YES/NO outcome shares (write TX)
- **Vault** — deposit collateral into FeeVault (write TX)
- **Governance** — delegate votes, view proposals, cast votes (write TX)

> After deploying the subgraph, update `SUBGRAPH_URL` in `frontend/app.js`.

---

## Subgraph

> To be completed by Member C.

The Graph subgraph will index:
- `MarketCreated`, `SharesBought`, `MarketResolved`
- `ProposalCreated`, `VoteCast`
- `LiquidityAdded`, `Swap`

---

## CI/CD

GitHub Actions runs on every push and pull request to `main`:

- `forge fmt --check`
- `forge build --sizes`
- `forge test` (unit/fuzz/invariant)
- `forge test` (fork — requires `MAINNET_RPC_URL` GitHub secret)
- `forge coverage`
- `forge snapshot --check`
- `slither contracts/`

PRs cannot be merged if CI is red.

---

## Security

- Slither: zero High/Medium findings
- CEI pattern and ReentrancyGuard on all state-changing functions
- AccessControl on all privileged functions
- No `tx.origin`, no `transfer`/`send`, SafeERC20 everywhere
- VULN-01 (reentrancy) and VULN-02 (access control) reproduced and fixed

See `docs/audit-report.md` for full findings.

---

## Documentation

> To be completed by Member C.

- `docs/architecture.md` — system diagrams, storage layout, design pattern ADRs
- `docs/audit-report.md` — security findings and mitigations
- `docs/gas-report.md` — Yul vs Solidity benchmarks, L1 vs L2 gas comparison
- `docs/coverage-report.md` — forge coverage output