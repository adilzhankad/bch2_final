"use client";

import { useState } from "react";
import { useAccount, useReadContract, useWriteContract, usePublicClient } from "wagmi";
import { parseEther, formatEther, maxUint256 } from "viem";
import {
  ADDRESSES,
  AMM_POOL_ABI,
  ERC20_ABI,
  POOL_FACTORY_ABI,
  ZERO_ADDRESS,
} from "@/config/contracts";
import { NetworkGuard } from "@/components/NetworkGuard";
import { TxButton } from "@/components/TxButton";

export default function SwapPage() {
  const { address } = useAccount();
  const [amountIn, setAmountIn] = useState("");
  const [zeroForOne, setZeroForOne] = useState(true); // token0 → token1

  // Resolve pool address: prefer NEXT_PUBLIC_AMM_POOL, otherwise look it up
  // on the factory using the two known tokens. This avoids hard-coding the
  // pool address in env every time we redeploy.
  const envPool = ADDRESSES.ammPool;
  const needsLookup = envPool === ZERO_ADDRESS;
  const { data: lookedUpPool } = useReadContract({
    address: ADDRESSES.poolFactory,
    abi: POOL_FACTORY_ABI,
    functionName: "getPool",
    args: [ADDRESSES.govToken, ADDRESSES.debtToken],
    query: {
      enabled:
        needsLookup &&
        ADDRESSES.poolFactory !== ZERO_ADDRESS &&
        ADDRESSES.govToken !== ZERO_ADDRESS &&
        ADDRESSES.debtToken !== ZERO_ADDRESS,
    },
  });

  const poolAddr = (needsLookup
    ? (lookedUpPool as `0x${string}` | undefined) ?? ZERO_ADDRESS
    : envPool) as `0x${string}`;
  const poolReady = poolAddr !== ZERO_ADDRESS;

  // Pool state
  const { data: token0 } = useReadContract({
    address: poolAddr, abi: AMM_POOL_ABI, functionName: "token0",
    query: { enabled: poolReady },
  });
  const { data: token1 } = useReadContract({
    address: poolAddr, abi: AMM_POOL_ABI, functionName: "token1",
    query: { enabled: poolReady },
  });
  const { data: reserves, refetch: refetchReserves } = useReadContract({
    address: poolAddr, abi: AMM_POOL_ABI, functionName: "getReserves",
    query: { enabled: poolReady },
  });

  const tokenIn  = (zeroForOne ? token0 : token1) as `0x${string}` | undefined;
  const tokenOut = (zeroForOne ? token1 : token0) as `0x${string}` | undefined;

  // User balances
  const { data: balIn, refetch: refetchBalIn } = useReadContract({
    address: tokenIn, abi: ERC20_ABI, functionName: "balanceOf",
    args: [address ?? "0x0000000000000000000000000000000000000000"],
    query: { enabled: !!address && !!tokenIn },
  });
  const { data: balOut, refetch: refetchBalOut } = useReadContract({
    address: tokenOut, abi: ERC20_ABI, functionName: "balanceOf",
    args: [address ?? "0x0000000000000000000000000000000000000000"],
    query: { enabled: !!address && !!tokenOut },
  });

  // Preview output
  const parsedIn = amountIn ? parseEther(amountIn) : 0n;
  const { data: amountOut } = useReadContract({
    address: poolAddr, abi: AMM_POOL_ABI, functionName: "getAmountOut",
    args: [parsedIn, zeroForOne],
    query: { enabled: poolReady && parsedIn > 0n },
  });

  // Allowance
  const { data: allowance, refetch: refetchAllowance } = useReadContract({
    address: tokenIn, abi: ERC20_ABI, functionName: "allowance",
    args: [address ?? ZERO_ADDRESS, poolAddr],
    query: { enabled: !!address && !!tokenIn && poolReady },
  });

  const { writeContractAsync } = useWriteContract();
  const publicClient = usePublicClient();

  const needsApprove = !allowance || (allowance as bigint) < parsedIn;

  const handleApprove = async () => {
    if (!tokenIn || !address) throw new Error("Wallet not connected");
    if (!poolReady) throw new Error("Pool not deployed");
    const hash = await writeContractAsync({
      address: tokenIn, abi: ERC20_ABI, functionName: "approve",
      args: [poolAddr, maxUint256],
    });
    await publicClient!.waitForTransactionReceipt({ hash });
    await refetchAllowance();
  };

  const handleSwap = async () => {
    if (!address || parsedIn === 0n) throw new Error("Invalid input");
    if (!poolReady) throw new Error("Pool not deployed");
    const minOut = amountOut ? (amountOut as bigint) * 99n / 100n : 0n; // 1% slippage
    await writeContractAsync({
      address: poolAddr, abi: AMM_POOL_ABI, functionName: "swapExactIn",
      args: [zeroForOne, parsedIn, minOut, address],
    });
    setAmountIn("");
    await Promise.all([refetchReserves(), refetchBalIn(), refetchBalOut()]);
  };

  const fmt = (v: bigint | undefined) =>
    v !== undefined ? Number(formatEther(v)).toFixed(4) : "—";

  return (
    <NetworkGuard>
      <div className="max-w-md mx-auto space-y-6">
        <h1 className="text-2xl font-bold">Swap</h1>

        {!poolReady && (
          <div className="card border border-yellow-500/40 text-yellow-200 text-sm">
            <p className="font-semibold">AMM pool is not deployed yet.</p>
            <p className="text-yellow-300/70 mt-1">
              Run <code>forge script script/Deploy.s.sol</code> (which now creates
              the DGT/mUSDC pool) and set <code>NEXT_PUBLIC_AMM_POOL</code> in{" "}
              <code>frontend/.env.local</code>, or just make sure{" "}
              <code>NEXT_PUBLIC_POOL_FACTORY</code> points to the live factory —
              this page will resolve the pool automatically.
            </p>
          </div>
        )}

        {/* Reserves */}
        <div className="card text-sm space-y-2">
          <p className="label">Pool Reserves</p>
          <div className="flex justify-between">
            <span className="text-gray-400">Token 0</span>
            <span className="font-mono">{fmt((reserves as [bigint, bigint])?.[0])}</span>
          </div>
          <div className="flex justify-between">
            <span className="text-gray-400">Token 1</span>
            <span className="font-mono">{fmt((reserves as [bigint, bigint])?.[1])}</span>
          </div>
        </div>

        {/* Swap Form */}
        <div className="card space-y-4">
          {/* Direction Toggle */}
          <div className="flex items-center justify-between">
            <span className="text-sm text-gray-400">
              {zeroForOne ? "Token0 → Token1" : "Token1 → Token0"}
            </span>
            <button
              className="btn-secondary text-sm py-1.5 w-auto px-4"
              onClick={() => setZeroForOne((v) => !v)}
            >
              Flip
            </button>
          </div>

          {/* Amount In */}
          <div>
            <p className="label">
              You Pay&nbsp;
              <span className="text-gray-500 text-xs">
                Balance: {fmt(balIn as bigint)}
              </span>
            </p>
            <input
              className="input"
              type="number"
              min="0"
              placeholder="0.0"
              value={amountIn}
              onChange={(e) => setAmountIn(e.target.value)}
            />
          </div>

          {/* Amount Out Preview */}
          <div>
            <p className="label">You Receive (est.)</p>
            <div className="input bg-gray-900 cursor-default">
              {amountOut !== undefined && parsedIn > 0n
                ? Number(formatEther(amountOut as bigint)).toFixed(6)
                : "—"}
            </div>
          </div>

          {/* Slippage note */}
          {amountOut !== undefined && parsedIn > 0n && (
            <p className="text-xs text-gray-500">1% slippage tolerance applied</p>
          )}

          {/* Approve if needed */}
          {needsApprove && parsedIn > 0n && (
            <TxButton
              label="Approve Token"
              loadingLabel="Approving..."
              onClick={handleApprove}
              variant="secondary"
            />
          )}

          <TxButton
            label="Swap"
            loadingLabel="Swapping..."
            onClick={handleSwap}
            disabled={!poolReady || parsedIn === 0n || needsApprove}
          />
        </div>
      </div>
    </NetworkGuard>
  );
}
