import { BigInt } from "@graphprotocol/graph-ts";
import { ProtocolStats } from "../generated/schema";

export function loadOrCreateStats(): ProtocolStats {
  let stats = ProtocolStats.load("global");
  if (stats == null) {
    stats = new ProtocolStats("global");
    stats.totalSwaps = BigInt.fromI32(0);
    stats.totalVolumeUSD = BigInt.fromI32(0);
    stats.totalVaultDeposits = BigInt.fromI32(0);
    stats.totalVaultTVL = BigInt.fromI32(0);
    stats.totalPools = BigInt.fromI32(0);
    stats.totalBorrows = BigInt.fromI32(0);
  }
  return stats as ProtocolStats;
}
