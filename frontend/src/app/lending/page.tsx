"use client";

import { useState } from "react";
import { useAccount, useReadContract, useWriteContract } from "wagmi";
import { parseEther, formatEther, maxUint256 } from "viem";
import { ADDRESSES, LENDING_POOL_ABI, ERC20_ABI } from "@/config/contracts";
import { NetworkGuard } from "@/components/NetworkGuard";
import { TxButton } from "@/components/TxButton";

// Collateral = GovToken (configured as isCollateral=true in deploy script).
// Debt token  = MockERC20 stablecoin (NEXT_PUBLIC_DEBT_TOKEN, configured as isBorrowable=true).
const COLL_TOKEN = ADDRESSES.govToken;
const DEBT_TOKEN = ADDRESSES.debtToken;

export default function LendingPage() {
  const { address } = useAccount();
  const [collAmount, setCollAmount] = useState("");
  const [borrowAmount, setBorrowAmount] = useState("");
  const [repayAmount, setRepayAmount] = useState("");

  // Pool stats
  const { data: totalLiquidity } = useReadContract({ address: ADDRESSES.lendingPool, abi: LENDING_POOL_ABI, functionName: "totalLiquidity", args: [DEBT_TOKEN] });
  const { data: totalBorrowed } = useReadContract({ address: ADDRESSES.lendingPool, abi: LENDING_POOL_ABI, functionName: "totalBorrowed", args: [DEBT_TOKEN] });
  const { data: borrowRate } = useReadContract({ address: ADDRESSES.lendingPool, abi: LENDING_POOL_ABI, functionName: "borrowRate", args: [DEBT_TOKEN] });

  // User position
  const { data: position, refetch: refetchPos } = useReadContract({
    address: ADDRESSES.lendingPool, abi: LENDING_POOL_ABI, functionName: "positions",
    args: [COLL_TOKEN, DEBT_TOKEN, address ?? "0x0000000000000000000000000000000000000000"],
    query: { enabled: !!address },
  });
  const { data: hf, refetch: refetchHf } = useReadContract({
    address: ADDRESSES.lendingPool, abi: LENDING_POOL_ABI, functionName: "healthFactor",
    args: [COLL_TOKEN, DEBT_TOKEN, address ?? "0x0000000000000000000000000000000000000000"],
    query: { enabled: !!address },
  });

  // Allowances
  const { data: collAllowance, refetch: refetchCollAllow } = useReadContract({
    address: COLL_TOKEN, abi: ERC20_ABI, functionName: "allowance",
    args: [address ?? "0x0000000000000000000000000000000000000000", ADDRESSES.lendingPool],
    query: { enabled: !!address },
  });
  const { data: debtAllowance, refetch: refetchDebtAllow } = useReadContract({
    address: DEBT_TOKEN, abi: ERC20_ABI, functionName: "allowance",
    args: [address ?? "0x0000000000000000000000000000000000000000", ADDRESSES.lendingPool],
    query: { enabled: !!address },
  });

  const { writeContractAsync } = useWriteContract();

  const parsedColl   = collAmount   ? parseEther(collAmount)   : 0n;
  const parsedBorrow = borrowAmount ? parseEther(borrowAmount) : 0n;
  const parsedRepay  = repayAmount  ? parseEther(repayAmount)  : 0n;

  const needsCollApprove = !collAllowance || (collAllowance as bigint) < parsedColl;
  const needsDebtApprove = !debtAllowance || (debtAllowance as bigint) < parsedRepay;

  const approveCollateral = async () => {
    if (!address) throw new Error("Not connected");
    await writeContractAsync({ address: COLL_TOKEN, abi: ERC20_ABI, functionName: "approve", args: [ADDRESSES.lendingPool, maxUint256] });
    await refetchCollAllow();
  };

  const approveDebt = async () => {
    if (!address) throw new Error("Not connected");
    await writeContractAsync({ address: DEBT_TOKEN, abi: ERC20_ABI, functionName: "approve", args: [ADDRESSES.lendingPool, maxUint256] });
    await refetchDebtAllow();
  };

  const handleBorrow = async () => {
    if (!address || parsedColl === 0n || parsedBorrow === 0n) throw new Error("Fill both fields");
    await writeContractAsync({
      address: ADDRESSES.lendingPool, abi: LENDING_POOL_ABI, functionName: "borrow",
      args: [COLL_TOKEN, parsedColl, DEBT_TOKEN, parsedBorrow],
    });
    setCollAmount(""); setBorrowAmount("");
    await Promise.all([refetchPos(), refetchHf()]);
  };

  const handleRepay = async () => {
    if (!address || parsedRepay === 0n) throw new Error("Enter repay amount");
    await writeContractAsync({
      address: ADDRESSES.lendingPool, abi: LENDING_POOL_ABI, functionName: "repay",
      args: [COLL_TOKEN, DEBT_TOKEN, parsedRepay],
    });
    setRepayAmount("");
    await Promise.all([refetchPos(), refetchHf()]);
  };

  const fmt = (v: bigint | undefined, dec = 4) =>
    v !== undefined ? Number(formatEther(v)).toFixed(dec) : "—";

  const hfNum = hf ? Number(formatEther(hf as bigint)) : Infinity;
  const hfColor = hfNum < 1.1 ? "text-red-400" : hfNum < 1.5 ? "text-yellow-400" : "text-green-400";

  const pos = position as [bigint, bigint, bigint] | undefined;

  return (
    <NetworkGuard>
      <div className="max-w-lg mx-auto space-y-6">
        <h1 className="text-2xl font-bold">Lending</h1>

        {/* Pool Stats */}
        <div className="card space-y-2 text-sm">
          <p className="label">Pool Stats</p>
          <div className="stat-row"><span className="text-gray-400">Total Liquidity</span><span className="font-mono">{fmt(totalLiquidity as bigint)}</span></div>
          <div className="stat-row"><span className="text-gray-400">Total Borrowed</span><span className="font-mono">{fmt(totalBorrowed as bigint)}</span></div>
          <div className="stat-row">
            <span className="text-gray-400">Borrow Rate (APR)</span>
            <span className="font-mono">
              {borrowRate !== undefined
                ? (Number(formatEther(borrowRate as bigint)) * 100).toFixed(2) + "%"
                : "—"}
            </span>
          </div>
        </div>

        {/* User Position */}
        <div className="card space-y-2 text-sm">
          <p className="label">Your Position</p>
          <div className="stat-row"><span className="text-gray-400">Collateral</span><span className="font-mono">{fmt(pos?.[0])}</span></div>
          <div className="stat-row"><span className="text-gray-400">Debt</span><span className="font-mono">{fmt(pos?.[1])}</span></div>
          <div className="stat-row">
            <span className="text-gray-400">Health Factor</span>
            <span className={`font-mono font-semibold ${hfColor}`}>
              {pos && pos[1] > 0n
                ? (hfNum === Infinity ? "inf" : hfNum.toFixed(3))
                : "—"}
            </span>
          </div>
        </div>

        {/* Borrow */}
        <div className="card space-y-4">
          <h2 className="font-semibold">Borrow</h2>
          <div>
            <p className="label">Collateral Amount</p>
            <input className="input" type="number" min="0" placeholder="0.0"
              value={collAmount} onChange={(e) => setCollAmount(e.target.value)} />
          </div>
          <div>
            <p className="label">Borrow Amount</p>
            <input className="input" type="number" min="0" placeholder="0.0"
              value={borrowAmount} onChange={(e) => setBorrowAmount(e.target.value)} />
          </div>
          {needsCollApprove && parsedColl > 0n && (
            <TxButton label="Approve Collateral" loadingLabel="Approving..." onClick={approveCollateral} variant="secondary" />
          )}
          <TxButton
            label="Borrow"
            loadingLabel="Borrowing..."
            onClick={handleBorrow}
            disabled={parsedColl === 0n || parsedBorrow === 0n || needsCollApprove}
          />
        </div>

        {/* Repay */}
        <div className="card space-y-4">
          <h2 className="font-semibold">Repay</h2>
          <div>
            <p className="label">Repay Amount</p>
            <input className="input" type="number" min="0" placeholder="0.0"
              value={repayAmount} onChange={(e) => setRepayAmount(e.target.value)} />
          </div>
          {needsDebtApprove && parsedRepay > 0n && (
            <TxButton label="Approve Debt Token" loadingLabel="Approving..." onClick={approveDebt} variant="secondary" />
          )}
          <TxButton
            label="Repay"
            loadingLabel="Repaying..."
            onClick={handleRepay}
            disabled={parsedRepay === 0n || needsDebtApprove}
          />
        </div>
      </div>
    </NetworkGuard>
  );
}
