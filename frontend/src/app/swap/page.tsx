"use client";

import { useState } from "react";
import { useAccount, useReadContract, useWriteContract, usePublicClient } from "wagmi";
import { parseEther, formatEther, maxUint256 } from "viem";
import { ADDRESSES, AMM_POOL_ABI, ERC20_ABI } from "@/config/contracts";
import { NetworkGuard } from "@/components/NetworkGuard";
import { TxButton } from "@/components/TxButton";

export default function SwapPage() {
  const { address } = useAccount();
  const [amountIn, setAmountIn] = useState("");
  const [zeroForOne, setZeroForOne] = useState(true); // token0 → token1

  // Pool state
  const { data: token0 } = useReadContract({ address: ADDRESSES.ammPool, abi: AMM_POOL_ABI, functionName: "token0" });
  const { data: token1 } = useReadContract({ address: ADDRESSES.ammPool, abi: AMM_POOL_ABI, functionName: "token1" });
  const { data: reserves, refetch: refetchReserves } = useReadContract({ address: ADDRESSES.ammPool, abi: AMM_POOL_ABI, functionName: "getReserves" });

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
    address: ADDRESSES.ammPool, abi: AMM_POOL_ABI, functionName: "getAmountOut",
    args: [parsedIn, zeroForOne],
    query: { enabled: parsedIn > 0n },
  });

  // Allowance
  const { data: allowance, refetch: refetchAllowance } = useReadContract({
    address: tokenIn, abi: ERC20_ABI, functionName: "allowance",
    args: [address ?? "0x0000000000000000000000000000000000000000", ADDRESSES.ammPool],
    query: { enabled: !!address && !!tokenIn },
  });

  const { writeContractAsync } = useWriteContract();
  const publicClient = usePublicClient();

  const needsApprove = !allowance || (allowance as bigint) < parsedIn;

  const handleApprove = async () => {
    if (!tokenIn || !address) throw new Error("Wallet not connected");
    const hash = await writeContractAsync({
      address: tokenIn, abi: ERC20_ABI, functionName: "approve",
      args: [ADDRESSES.ammPool, maxUint256],
    });
    await publicClient!.waitForTransactionReceipt({ hash });
    await refetchAllowance();
  };

  const handleSwap = async () => {
    if (!address || parsedIn === 0n) throw new Error("Invalid input");
    const minOut = amountOut ? (amountOut as bigint) * 99n / 100n : 0n; // 1% slippage
    await writeContractAsync({
      address: ADDRESSES.ammPool, abi: AMM_POOL_ABI, functionName: "swapExactIn",
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
            disabled={parsedIn === 0n || needsApprove}
          />
        </div>
      </div>
    </NetworkGuard>
  );
}
