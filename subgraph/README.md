# Prediction Market Subgraph

Indexes events from the PredictionMarket contract on Base Sepolia.

## Deployed on Goldsky

**Public GraphQL endpoint:**
```
https://api.goldsky.com/api/public/project_cmp9m4o9exste01uedkt57uez/subgraphs/prediction-market/1.0.0/gn
```

Network: Base Sepolia (chain 84532)
Contract: `0x0cEC8fd1fD75bFe985807BeEEC1ACdaBE1784bB7`
Start block: `41580684`

## Entities

| Entity | Description |
|---|---|
| `Market` | Binary outcome market with question, state, collateral |
| `Trade` | Individual share purchase (YES or NO) |
| `Proposal` | Governance proposal |
| `Vote` | Vote cast on a proposal |
| `LPPosition` | Liquidity provider position in CPMM |

## Example GraphQL Queries

### Get all markets
```graphql
{
  markets(first: 10, orderBy: createdAt, orderDirection: desc) {
    id
    question
    state
    totalCollateral
    yesShares
    noShares
    createdAt
  }
}
```

### Get trades for a market
```graphql
{
  trades(where: { market: "0" }, orderBy: timestamp, orderDirection: desc) {
    buyer
    isYes
    collateralIn
    sharesMinted
    timestamp
  }
}
```

### Get recent trades by a user
```graphql
{
  trades(where: { buyer: "0xYOUR_ADDRESS" }, first: 10) {
    market { question }
    isYes
    collateralIn
    sharesMinted
  }
}
```

### Get active markets
```graphql
{
  markets(where: { state: 0 }) {
    id
    question
    resolutionTime
    totalCollateral
  }
}
```

### Get top markets by collateral
```graphql
{
  markets(orderBy: totalCollateral, orderDirection: desc, first: 5) {
    id
    question
    totalCollateral
    yesShares
    noShares
  }
}
```