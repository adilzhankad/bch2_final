"use client";

import { useState } from "react";
import { useAccount, useReadContract, useWriteContract, usePublicClient } from "wagmi";
import { parseEther, formatEther, maxUint256 } from "viem";
import { ADDRESSES, YIELD_VAULT_ABI, ERC20_ABI } from "@/config/contracts";
import { NetworkGuard } from "@/components/NetworkGuard";
import { TxButton } from "@/components/TxButton";

type Mode = "deposit" | "redeem";

export default function VaultPage() {
  const { address } = useAccount();
  const [mode, setMode] = useState<Mode>("deposit");
  const [amount, setAmount] = useState("");

  // Vault state
  const { data: assetAddr } = useReadContract({ address: ADDRESSES.yieldVault, abi: YIELD_VAULT_ABI, functionName: "asset" });
  const { data: totalAssets, refetch: refetchTvl } = useReadContract({ address: ADDRESSES.yieldVault, abi: YIELD_VAULT_ABI, functionName: "totalAssets" });
  const { data: totalSupply } = useReadContract({ address: ADDRESSES.yieldVault, abi: YIELD_VAULT_ABI, functionName: "totalSupply" });
  const { data: paused } = useReadContract({ address: ADDRESSES.yieldVault, abi: YIELD_VAULT_ABI, functionName: "paused" });

  // User state
  const { data: shares, refetch: refetchShares } = useReadContract({
    address: ADDRESSES.yieldVault, abi: YIELD_VAULT_ABI, functionName: "balanceOf",
    args: [address ?? "0x0000000000000000000000000000000000000000"],
    query: { enabled: !!address },
  });
  const { data: assetBalance, refetch: refetchAssetBal } = useReadContract({
    address: assetAddr as `0x${string}` | undefined, abi: ERC20_ABI, functionName: "balanceOf",
    args: [address ?? "0x0000000000000000000000000000000000000000"],
    query: { enabled: !!address && !!assetAddr },
  });
  const { data: allowance, refetch: refetchAllowance } = useReadContract({
    address: assetAddr as `0x${string}` | undefined, abi: ERC20_ABI, functionName: "allowance",
    args: [address ?? "0x0000000000000000000000000000000000000000", ADDRESSES.yieldVault],
    query: { enabled: !!address && !!assetAddr },
  });

  // Share price
  const { data: assetsPerShare } = useReadContract({
    address: ADDRESSES.yieldVault, abi: YIELD_VAULT_ABI, functionName: "convertToAssets",
    args: [parseEther("1")],
  });

  // Preview
  const parsed = amount ? parseEther(amount) : 0n;
  const { data: previewOut } = useReadContract({
    address: ADDRESSES.yieldVault, abi: YIELD_VAULT_ABI,
    functionName: mode === "deposit" ? "previewDeposit" : "previewRedeem",
    args: [parsed],
    query: { enabled: parsed > 0n },
  });

  const { writeContractAsync } = useWriteContract();
  const publicClient = usePublicClient();

  const needsApprove = mode === "deposit" && (!allowance || (allowance as bigint) < parsed);

  const handleApprove = async () => {
    if (!assetAddr || !address) throw new Error("Not ready");
    const hash = await writeContractAsync({
      address: assetAddr as `0x${string}`, abi: ERC20_ABI,
      functionName: "approve", args: [ADDRESSES.yieldVault, maxUint256],
    });
    await publicClient!.waitForTransactionReceipt({ hash });
    await refetchAllowance();
  };

  const handleDeposit = async () => {
    if (!address || parsed === 0n) throw new Error("Invalid amount");
    await writeContractAsync({
      address: ADDRESSES.yieldVault, abi: YIELD_VAULT_ABI,
      functionName: "deposit", args: [parsed, address],
    });
    setAmount("");
    await Promise.all([refetchShares(), refetchAssetBal(), refetchTvl()]);
  };

  const handleRedeem = async () => {
    if (!address || parsed === 0n) throw new Error("Invalid amount");
    await writeContractAsync({
      address: ADDRESSES.yieldVault, abi: YIELD_VAULT_ABI,
      functionName: "redeem", args: [parsed, address, address],
    });
    setAmount("");
    await Promise.all([refetchShares(), refetchAssetBal(), refetchTvl()]);
  };

  const fmt = (v: bigint | undefined, dec = 4) =>
    v !== undefined ? Number(formatEther(v)).toFixed(dec) : "—";

  return (
    <NetworkGuard>
      <div className="max-w-md mx-auto space-y-6">
        <h1 className="text-2xl font-bold">Yield Vault</h1>

        {/* Stats */}
        <div className="card space-y-2 text-sm">
          <p className="label">Vault Stats</p>
          <div className="stat-row"><span className="text-gray-400">TVL</span><span className="font-mono">{fmt(totalAssets as bigint)} tokens</span></div>
          <div className="stat-row"><span className="text-gray-400">Total Shares</span><span className="font-mono">{fmt(totalSupply as bigint)}</span></div>
          <div className="stat-row"><span className="text-gray-400">Share Price</span><span className="font-mono">{fmt(assetsPerShare as bigint, 6)} tokens/share</span></div>
          {paused && <p className="text-yellow-400 text-xs">Vault is paused — deposits/withdrawals disabled.</p>}
        </div>

        {/* User Position */}
        <div className="card space-y-2 text-sm">
          <p className="label">Your Position</p>
          <div className="stat-row"><span className="text-gray-400">Shares Held</span><span className="font-mono">{fmt(shares as bigint)}</span></div>
          <div className="stat-row"><span className="text-gray-400">Wallet Balance</span><span className="font-mono">{fmt(assetBalance as bigint)} tokens</span></div>
        </div>

        {/* Action Card */}
        <div className="card space-y-4">
          {/* Mode Toggle */}
          <div className="flex bg-gray-800 rounded-xl p-1 gap-1">
            {(["deposit", "redeem"] as Mode[]).map((m) => (
              <button
                key={m}
                className={`flex-1 py-2 rounded-lg text-sm font-medium capitalize transition-colors
                  ${mode === m ? "bg-brand-500 text-white" : "text-gray-400 hover:text-white"}`}
                onClick={() => { setMode(m); setAmount(""); }}
              >
                {m}
              </button>
            ))}
          </div>

          <div>
            <p className="label">
              {mode === "deposit" ? "Assets to Deposit" : "Shares to Redeem"}
              <span className="ml-2 text-gray-500 text-xs">
                {mode === "deposit"
                  ? `Balance: ${fmt(assetBalance as bigint)}`
                  : `Shares: ${fmt(shares as bigint)}`}
              </span>
            </p>
            <input
              className="input"
              type="number"
              min="0"
              placeholder="0.0"
              value={amount}
              onChange={(e) => setAmount(e.target.value)}
              disabled={!!paused}
            />
          </div>

          {parsed > 0n && previewOut !== undefined && (
            <p className="text-sm text-gray-400">
              You will receive ~{fmt(previewOut as bigint, 6)}{" "}
              {mode === "deposit" ? "shares" : "tokens"}
            </p>
          )}

          {mode === "deposit" && needsApprove && parsed > 0n && (
            <TxButton label="Approve" loadingLabel="Approving..." onClick={handleApprove} variant="secondary" />
          )}

          <TxButton
            label={mode === "deposit" ? "Deposit" : "Redeem"}
            loadingLabel={mode === "deposit" ? "Depositing..." : "Redeeming..."}
            onClick={mode === "deposit" ? handleDeposit : handleRedeem}
            disabled={parsed === 0n || !!paused || (mode === "deposit" && needsApprove)}
          />
        </div>
      </div>
    </NetworkGuard>
  );
}
