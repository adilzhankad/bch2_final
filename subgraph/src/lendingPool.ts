import {
  Deposited,
  Withdrawn,
  Borrowed,
  Repaid,
  Liquidated,
} from "../generated/LendingPool/LendingPool";
import {
  LendingDeposit,
  LendingWithdrawal,
  Borrow,
  Repay,
  Liquidation,
} from "../generated/schema";
import { BigInt } from "@graphprotocol/graph-ts";
import { loadOrCreateStats } from "./utils";

export function handleDeposited(event: Deposited): void {
  let id = event.transaction.hash.toHex() + "-" + event.logIndex.toString();
  let deposit = new LendingDeposit(id);
  deposit.user = event.params.user;
  deposit.token = event.params.token;
  deposit.amount = event.params.amount;
  deposit.timestamp = event.block.timestamp;
  deposit.blockNumber = event.block.number;
  deposit.save();
}

export function handleWithdrawn(event: Withdrawn): void {
  let id = event.transaction.hash.toHex() + "-" + event.logIndex.toString();
  let withdrawal = new LendingWithdrawal(id);
  withdrawal.user = event.params.user;
  withdrawal.token = event.params.token;
  withdrawal.amount = event.params.amount;
  withdrawal.timestamp = event.block.timestamp;
  withdrawal.blockNumber = event.block.number;
  withdrawal.save();
}

export function handleBorrowed(event: Borrowed): void {
  let id = event.transaction.hash.toHex() + "-" + event.logIndex.toString();
  let borrow = new Borrow(id);
  borrow.user = event.params.user;
  borrow.collateral = event.params.collateral;
  borrow.debt = event.params.debt;
  borrow.amount = event.params.amount;
  borrow.timestamp = event.block.timestamp;
  borrow.blockNumber = event.block.number;
  borrow.save();

  let stats = loadOrCreateStats();
  stats.totalBorrows = stats.totalBorrows.plus(BigInt.fromI32(1));
  stats.save();
}

export function handleRepaid(event: Repaid): void {
  let id = event.transaction.hash.toHex() + "-" + event.logIndex.toString();
  let repay = new Repay(id);
  repay.user = event.params.user;
  repay.collateral = event.params.collateral;
  repay.debt = event.params.debt;
  repay.amount = event.params.amount;
  repay.timestamp = event.block.timestamp;
  repay.blockNumber = event.block.number;
  repay.save();
}

export function handleLiquidated(event: Liquidated): void {
  let id = event.transaction.hash.toHex() + "-" + event.logIndex.toString();
  let liq = new Liquidation(id);
  liq.liquidator = event.params.liquidator;
  liq.user = event.params.user;
  liq.collateral = event.params.collateral;
  liq.debt = event.params.debt;
  liq.debtRepaid = event.params.debtRepaid;
  liq.collateralSeized = event.params.collateralSeized;
  liq.timestamp = event.block.timestamp;
  liq.blockNumber = event.block.number;
  liq.save();
}
