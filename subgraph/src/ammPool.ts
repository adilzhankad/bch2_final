import {
  Swap as SwapEvent,
  Mint as MintEvent,
  Burn as BurnEvent,
  Sync as SyncEvent,
} from "../generated/templates/AMMPool/AMMPool";
import { Pool, Swap, LiquidityEvent } from "../generated/schema";
import { BigInt } from "@graphprotocol/graph-ts";
import { loadOrCreateStats } from "./utils";

export function handleSwap(event: SwapEvent): void {
  let poolId = event.address.toHex();
  let pool = Pool.load(poolId);
  if (pool == null) return;

  let id = event.transaction.hash.toHex() + "-" + event.logIndex.toString();
  let swap = new Swap(id);
  swap.pool = poolId;
  swap.sender = event.params.sender;
  swap.amount0In = event.params.amount0In;
  swap.amount1In = event.params.amount1In;
  swap.amount0Out = event.params.amount0Out;
  swap.amount1Out = event.params.amount1Out;

  // Convenience aggregates expected by the frontend.
  swap.amountIn = event.params.amount0In.gt(BigInt.fromI32(0))
    ? event.params.amount0In
    : event.params.amount1In;
  swap.amountOut = event.params.amount0Out.gt(BigInt.fromI32(0))
    ? event.params.amount0Out
    : event.params.amount1Out;

  swap.timestamp = event.block.timestamp;
  swap.blockNumber = event.block.number;
  swap.save();

  pool.swapCount = pool.swapCount.plus(BigInt.fromI32(1));
  pool.save();

  let stats = loadOrCreateStats();
  stats.totalSwaps = stats.totalSwaps.plus(BigInt.fromI32(1));
  // totalVolumeUSD uses raw token units as a proxy (no price oracle in subgraph).
  stats.totalVolumeUSD = stats.totalVolumeUSD.plus(swap.amountIn);
  stats.save();
}

export function handleMint(event: MintEvent): void {
  let id = event.transaction.hash.toHex() + "-" + event.logIndex.toString();
  let liq = new LiquidityEvent(id);
  liq.pool = event.address.toHex();
  liq.type = "MINT";
  liq.sender = event.params.sender;
  liq.amount0 = event.params.amount0;
  liq.amount1 = event.params.amount1;
  liq.timestamp = event.block.timestamp;
  liq.blockNumber = event.block.number;
  liq.save();
}

export function handleBurn(event: BurnEvent): void {
  let id = event.transaction.hash.toHex() + "-" + event.logIndex.toString();
  let liq = new LiquidityEvent(id);
  liq.pool = event.address.toHex();
  liq.type = "BURN";
  liq.sender = event.params.sender;
  liq.amount0 = event.params.amount0;
  liq.amount1 = event.params.amount1;
  liq.timestamp = event.block.timestamp;
  liq.blockNumber = event.block.number;
  liq.save();
}

export function handleSync(event: SyncEvent): void {
  let pool = Pool.load(event.address.toHex());
  if (pool == null) return;
  pool.reserve0 = event.params.reserve0;
  pool.reserve1 = event.params.reserve1;
  pool.save();
}
