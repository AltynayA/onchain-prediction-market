# Architecture Document

**Project:** On-Chain Prediction Market  
**Version:** 1.0  
**Network:** Base Sepolia (chain 84532)  
**Date:** May 2026

---

## 1. System Overview

The On-Chain Prediction Market is a decentralized protocol that allows users to trade binary-outcome shares on real-world events. The protocol consists of five main subsystems: the prediction market core, a constant-product AMM, an ERC-4626 fee vault, a Chainlink oracle adapter, and an OZ Governor DAO.

All protocol parameters (dispute window, fee vault address, oracle staleness) are controlled exclusively by the DAO through a Timelock — no admin backdoor exists after deployment.

---

## 2. High-Level Architecture

```
┌─────────────────────────────────────────────────────────┐
│                        Users                            │
└──────────────┬──────────────────────────┬───────────────┘
               │                          │
               ▼                          ▼
┌──────────────────────┐    ┌─────────────────────────┐
│  PredictionMarket    │    │          CPMM            │
│  (UUPS Proxy)        │    │  (x·y=k AMM, 0.3% fee)  │
│                      │    │                         │
│  - createMarket()    │    │  - addLiquidity()       │
│  - buyShares()       │    │  - removeLiquidity()    │
│  - resolveMarket()   │    │  - swap()               │
│  - redeemShares()    │    │  - getAmountOut()       │
└──────┬───────────────┘    └────────────┬────────────┘
       │                                 │
       ▼                                 ▼
┌──────────────┐              ┌──────────────────────┐
│ OutcomeToken │              │   OutcomeToken        │
│ (ERC-1155)   │              │   (shared)            │
│ YES (id=0)   │              └──────────────────────┘
│ NO  (id=1)   │
└──────────────┘
       │
       ▼
┌──────────────┐    ┌──────────────────┐    ┌──────────────────┐
│  FeeVault    │    │  OracleAdapter   │    │  MarketFactory   │
│  (ERC-4626)  │    │  (Chainlink)     │    │  CREATE/CREATE2  │
└──────────────┘    └──────────────────┘    └──────────────────┘

┌─────────────────────────────────────────────────────────┐
│                    Governance Layer                      │
│                                                         │
│  GovernanceToken (ERC20Votes)                          │
│       └─► MarketGovernor (OZ Governor)                 │
│               └─► MarketTimelock (2-day delay)         │
│                       └─► controls PredictionMarket    │
└─────────────────────────────────────────────────────────┘
```

---

## 3. Contract Descriptions

### 3.1 PredictionMarket.sol

The core contract. Deployed as a UUPS proxy so it can be upgraded via governance vote.

**State machine:**
```
Active ──► Pending ──► Final
                 └──► Disputed ──► Final
```

**Key functions:**
- `createMarket()` — admin creates a new binary market with a question and resolution time
- `buyShares()` — user deposits mUSDC, receives YES (id=0) or NO (id=1) ERC-1155 shares. 1% fee goes to FeeVault
- `resolveMarket()` — resolver calls after resolution time; oracle staleness is checked
- `disputeMarket()` — anyone can dispute during the dispute window (2 days)
- `finalizeMarket()` — anyone can finalize after dispute window expires
- `redeemShares()` — winning side redeems shares for proportional collateral

**Security:**
- CEI pattern enforced on all state-changing functions
- `nonReentrant` on `buyShares`, `resolveMarket`, `redeemShares`
- `SafeERC20` for all collateral transfers
- `Pausable` circuit breaker controlled by `PAUSER_ROLE`

### 3.2 CPMM.sol

Constant-product AMM for trading outcome shares. Implements x·y=k with 0.3% swap fee.

**Key functions:**
- `addLiquidity()` — deposit YES+NO shares, receive LP tokens
- `removeLiquidity()` — burn LP tokens, receive proportional YES+NO shares
- `swap()` — trade YES for NO or vice versa
- `impliedProbabilityYes()` — returns current market probability

**LP token:** tracked internally (not ERC-20). First depositor locks 1000 MINIMUM_LIQUIDITY tokens to prevent inflation attacks.

**Yul optimization:** core `_getAmountOutYul()` is implemented in assembly for gas savings. Benchmarked against Solidity equivalent — see `docs/gas-report.md`.

### 3.3 FeeVault.sol

ERC-4626 tokenized vault. Receives 1% fees from every `buyShares()` call. LP holders can deposit additional collateral and receive `vPRED` vault shares proportional to their contribution.

**ERC-4626 rounding:** all rounding is in favour of the vault (never in favour of the user), as required by the standard.

### 3.4 OracleAdapter.sol

Wraps a Chainlink AggregatorV3Interface. Decouples the market contract from any specific oracle implementation.

**Key functions:**
- `getPrice()` — returns latest price, reverts if stale
- `assertFresh(uint256 maxAge)` — called by `resolveMarket()` to verify data freshness

### 3.5 MarketFactory.sol

Deploys new `PredictionMarket` proxy instances. Supports both CREATE (nonce-based) and CREATE2 (deterministic address). CREATE2 allows pre-approval of market addresses before deployment.

### 3.6 GovernanceToken.sol (PredictionToken)

ERC20Votes + ERC20Permit token. 1,000,000 PRED total supply distributed at deployment:
- 40% Team
- 30% Treasury
- 20% Community
- 10% Liquidity

Voting power is checkpointed per block. Holders must delegate (to themselves or others) to activate voting power.

### 3.7 MarketGovernor.sol

OpenZeppelin Governor stack with:
- Voting delay: 1 day
- Voting period: 1 week
- Quorum: 4% of total supply
- Proposal threshold: 1% of total supply (dynamic, scales with supply)

### 3.8 MarketTimelock.sol

TimelockController with 2-day minimum delay. The Timelock holds `DEFAULT_ADMIN_ROLE` on `PredictionMarket` — all protocol parameter changes must pass through governance and wait 2 days before execution.

---

## 4. Storage Layout — PredictionMarket V1 → V2

V1 uses a `__gap[44]` storage reservation for future upgrades. V2 consumes 2 slots from this gap.

```
Slot  Contract / Variable
────────────────────────────────────────────────
0     Initializable._initialized
1     AccessControl._roles
2     AccessControl._roleMembers
3     Pausable._paused
4     (ReentrancyGuard — stateless in OZ v5)
5     PredictionMarket.markets
6     PredictionMarket.marketCount
7     PredictionMarket.collateral
8     PredictionMarket.outcomeToken
9     PredictionMarket.defaultStaleness
10    PredictionMarket.defaultDisputeWindow
11    PredictionMarket.feeVault
12    __gap[0]  →  V2: emergencyRecipient
13    __gap[1]  →  V2: marketFeeBps mapping
14-55 __gap[2..43]  (reserved for future use)
```

No storage collision between V1 and V2. V3 must append after slot 55.

---

## 5. Sequence Diagrams

### 5.1 Buy Shares Flow

```
User          PredictionMarket      CollateralToken    OutcomeToken    FeeVault
 │                   │                    │                │              │
 │─buyShares()──────►│                    │                │              │
 │                   │─safeTransferFrom()►│                │              │
 │                   │◄───────────────────│                │              │
 │                   │─safeTransfer(fee)──────────────────────────────────►│
 │                   │─mint(shares)────────────────────────►│              │
 │◄──────────────────│                    │                │              │
```

### 5.2 Governance Propose → Execute Flow

```
Proposer    MarketGovernor     MarketTimelock    PredictionMarket
   │               │                 │                 │
   │─propose()────►│                 │                 │
   │               │  (1 day delay)  │                 │
   │─castVote()───►│                 │                 │
   │               │  (1 week vote)  │                 │
   │─queue()───────►─schedule()─────►│                 │
   │               │  (2 day delay)  │                 │
   │─execute()─────►─execute()──────►─setDisputeWindow►│
   │               │                 │                 │
```

### 5.3 Resolve → Redeem Flow

```
Resolver    PredictionMarket    OracleAdapter    Winner
   │               │                 │             │
   │─resolveMarket►│                 │             │
   │               │─assertFresh()──►│             │
   │               │◄────────────────│             │
   │               │  (state=Pending)│             │
   │               │  (2 day window) │             │
   │           finalizeMarket()      │             │
   │               │  (state=Final)  │             │
   │               │                 │─redeemShares►│
   │               │◄────────────────────────────── │
   │               │─safeTransfer(collateral)──────►│
```

---

## 6. Design Pattern ADRs

### ADR-1: UUPS over Transparent Proxy
**Decision:** Use UUPS (EIP-1822) instead of Transparent proxy.  
**Reason:** Lower gas cost for users (no admin check on every call). Upgrade logic lives in implementation, not proxy. OpenZeppelin recommends UUPS for new projects.

### ADR-2: ERC-1155 for Outcome Shares
**Decision:** Use ERC-1155 with token id 0 (YES) and 1 (NO) instead of two separate ERC-20 tokens.  
**Reason:** Single contract for both outcomes. Batch transfers possible. Less deployment gas.

### ADR-3: Pull-over-Push for Redemptions
**Decision:** Winners call `redeemShares()` themselves instead of auto-distributing.  
**Reason:** Eliminates reentrancy risk from external calls during distribution. No gas limit issues with large winner sets.

### ADR-4: Stateless ReentrancyGuard (OZ v5)
**Decision:** Import `ReentrancyGuard` from `@openzeppelin/contracts` (not upgradeable package).  
**Reason:** OZ v5 removed `ReentrancyGuardUpgradeable` — guard is now stateless (uses transient storage EIP-1153). Safe to mix with upgradeable base contracts.

### ADR-5: Dynamic Proposal Threshold
**Decision:** `proposalThreshold()` returns 1% of `getPastTotalSupply(block.number - 1)` dynamically instead of a fixed value.  
**Reason:** Threshold scales with token supply changes over time. Fixed values become irrelevant after token distributions or burns.