import {
  Deposit as DepositEvent,
  Withdraw as WithdrawEvent,
  YieldInjected,
} from "../generated/YieldVault/YieldVault";
import { Deposit, VaultWithdrawal, YieldInjection } from "../generated/schema";
import { BigInt } from "@graphprotocol/graph-ts";
import { loadOrCreateStats } from "./utils";

export function handleVaultDeposit(event: DepositEvent): void {
  let id = event.transaction.hash.toHex() + "-" + event.logIndex.toString();
  let deposit = new Deposit(id);
  deposit.caller = event.params.sender; // ERC-4626: "sender" == the caller
  deposit.owner = event.params.owner;
  deposit.assets = event.params.assets;
  deposit.shares = event.params.shares;
  deposit.timestamp = event.block.timestamp;
  deposit.blockNumber = event.block.number;
  deposit.save();

  let stats = loadOrCreateStats();
  stats.totalVaultDeposits = stats.totalVaultDeposits.plus(BigInt.fromI32(1));
  stats.totalVaultTVL = stats.totalVaultTVL.plus(event.params.assets);
  stats.save();
}

export function handleVaultWithdraw(event: WithdrawEvent): void {
  let id = event.transaction.hash.toHex() + "-" + event.logIndex.toString();
  let withdrawal = new VaultWithdrawal(id);
  withdrawal.sender = event.params.sender;
  withdrawal.receiver = event.params.receiver;
  withdrawal.owner = event.params.owner;
  withdrawal.assets = event.params.assets;
  withdrawal.shares = event.params.shares;
  withdrawal.timestamp = event.block.timestamp;
  withdrawal.blockNumber = event.block.number;
  withdrawal.save();

  let stats = loadOrCreateStats();
  let tvl = stats.totalVaultTVL;
  stats.totalVaultTVL = tvl.gt(event.params.assets)
    ? tvl.minus(event.params.assets)
    : BigInt.fromI32(0);
  stats.save();
}

export function handleYieldInjected(event: YieldInjected): void {
  let id = event.transaction.hash.toHex() + "-" + event.logIndex.toString();
  let injection = new YieldInjection(id);
  injection.by = event.params.by;
  injection.amount = event.params.amount;
  injection.timestamp = event.block.timestamp;
  injection.blockNumber = event.block.number;
  injection.save();

  // Injected yield increases TVL (only the net amount reaches the vault).
  let stats = loadOrCreateStats();
  stats.totalVaultTVL = stats.totalVaultTVL.plus(event.params.amount);
  stats.save();
}
