import { BigInt, Bytes } from "@graphprotocol/graph-ts";
import {
  MarketCreated,
  SharesBought,
  MarketResolved,
  MarketFinalized,
  SharesRedeemed,
} from "../generated/PredictionMarket/PredictionMarket";
import { Market, Trade } from "../generated/schema";

// handle new market created
export function handleMarketCreated(event: MarketCreated): void {
  let market = new Market(event.params.marketId.toString());
  market.question = event.params.question;
  market.resolutionTime = event.params.resolutionTime;
  market.oracleAdapter = event.params.oracleAdapter;
  market.state = 0; // Active
  market.outcome = false;
  market.totalCollateral = BigInt.fromI32(0);
  market.yesShares = BigInt.fromI32(0);
  market.noShares = BigInt.fromI32(0);
  market.createdAt = event.block.timestamp;
  market.save();
}

// handle shares bought
export function handleSharesBought(event: SharesBought): void {
  let market = Market.load(event.params.marketId.toString());
  if (!market) return;

  // update market totals
  market.totalCollateral = market.totalCollateral.plus(event.params.collateralIn);
  if (event.params.isYes) {
    market.yesShares = market.yesShares.plus(event.params.sharesMinted);
  } else {
    market.noShares = market.noShares.plus(event.params.sharesMinted);
  }
  market.save();

  // create trade record
  let tradeId = event.transaction.hash.toHex() + "-" + event.logIndex.toString();
  let trade = new Trade(tradeId);
  trade.market = market.id;
  trade.buyer = event.params.buyer;
  trade.isYes = event.params.isYes;
  trade.collateralIn = event.params.collateralIn;
  trade.sharesMinted = event.params.sharesMinted;
  trade.timestamp = event.block.timestamp;
  trade.blockNumber = event.block.number;
  trade.save();
}

// handle market resolved
export function handleMarketResolved(event: MarketResolved): void {
  let market = Market.load(event.params.marketId.toString());
  if (!market) return;
  market.state = 1; // Pending
  market.outcome = event.params.outcome;
  market.save();
}

// handle market finalized 
export function handleMarketFinalized(event: MarketFinalized): void {
  let market = Market.load(event.params.marketId.toString());
  if (!market) return;
  market.state = 3; // Final
  market.outcome = event.params.outcome;
  market.save();
}

// handle shares redeemed 
export function handleSharesRedeemed(event: SharesRedeemed): void {
  let market = Market.load(event.params.marketId.toString());
  if (!market) return;
  market.totalCollateral = market.totalCollateral.minus(event.params.collateralOut);
  market.save();
}