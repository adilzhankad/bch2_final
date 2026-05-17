import { PoolCreated } from "../generated/PoolFactory/PoolFactory";
import { Pool } from "../generated/schema";
import { AMMPool } from "../generated/templates";
import { BigInt } from "@graphprotocol/graph-ts";
import { loadOrCreateStats } from "./utils";

export function handlePoolCreated(event: PoolCreated): void {
  let pool = new Pool(event.params.pool.toHex());
  pool.token0 = event.params.token0;
  pool.token1 = event.params.token1;
  pool.reserve0 = BigInt.fromI32(0);
  pool.reserve1 = BigInt.fromI32(0);
  pool.swapCount = BigInt.fromI32(0);
  pool.createdAt = event.block.timestamp;
  pool.save();

  // Spin up a dynamic data source for this pool's events.
  AMMPool.create(event.params.pool);

  let stats = loadOrCreateStats();
  stats.totalPools = stats.totalPools.plus(BigInt.fromI32(1));
  stats.save();
}
