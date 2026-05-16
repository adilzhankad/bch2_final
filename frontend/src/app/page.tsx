"use client";

import Link from "next/link";
import { useAccount } from "wagmi";
import { useReadContract } from "wagmi";
import { ADDRESSES, GOV_TOKEN_ABI, AMM_POOL_ABI, YIELD_VAULT_ABI } from "@/config/contracts";
import { formatEther } from "viem";

export default function Home() {
  const { address, isConnected } = useAccount();

  const { data: govBalance } = useReadContract({
    address: ADDRESSES.govToken,
    abi: GOV_TOKEN_ABI,
    functionName: "balanceOf",
    args: [address ?? "0x0000000000000000000000000000000000000000"],
    query: { enabled: !!address },
  });

  const { data: votingPower } = useReadContract({
    address: ADDRESSES.govToken,
    abi: GOV_TOKEN_ABI,
    functionName: "getVotes",
    args: [address ?? "0x0000000000000000000000000000000000000000"],
    query: { enabled: !!address },
  });

  const { data: reserves } = useReadContract({
    address: ADDRESSES.ammPool,
    abi: AMM_POOL_ABI,
    functionName: "getReserves",
  });

  const { data: vaultTvl } = useReadContract({
    address: ADDRESSES.yieldVault,
    abi: YIELD_VAULT_ABI,
    functionName: "totalAssets",
  });

  const fmt = (v: bigint | undefined, decimals = 2) =>
    v !== undefined ? Number(formatEther(v)).toFixed(decimals) : "—";

  return (
    <div className="space-y-8">
      <div>
        <h1 className="text-3xl font-bold">DeFi Super-App</h1>
        <p className="text-gray-400 mt-1">AMM · Lending · ERC-4626 Vault · DAO Governance</p>
      </div>

      {/* Wallet Stats */}
      {isConnected && (
        <div className="card space-y-3">
          <h2 className="font-semibold text-gray-300 text-sm uppercase tracking-wider">Your Wallet</h2>
          <div className="stat-row">
            <span className="text-gray-400">DGT Balance</span>
            <span className="font-mono">{fmt(govBalance as bigint)} DGT</span>
          </div>
          <div className="stat-row">
            <span className="text-gray-400">Voting Power</span>
            <span className="font-mono">{fmt(votingPower as bigint)} DGT</span>
          </div>
        </div>
      )}

      {/* Protocol Stats */}
      <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
        <div className="card space-y-3">
          <h2 className="font-semibold text-gray-300 text-sm uppercase tracking-wider">AMM Pool</h2>
          <div className="stat-row">
            <span className="text-gray-400">Reserve 0</span>
            <span className="font-mono">{fmt(reserves?.[0] as bigint)}</span>
          </div>
          <div className="stat-row">
            <span className="text-gray-400">Reserve 1</span>
            <span className="font-mono">{fmt(reserves?.[1] as bigint)}</span>
          </div>
        </div>
        <div className="card space-y-3">
          <h2 className="font-semibold text-gray-300 text-sm uppercase tracking-wider">Yield Vault</h2>
          <div className="stat-row">
            <span className="text-gray-400">TVL</span>
            <span className="font-mono">{fmt(vaultTvl as bigint)}</span>
          </div>
        </div>
      </div>

      {/* Quick Links */}
      <div className="grid grid-cols-2 sm:grid-cols-4 gap-3">
        {[
          { href: "/swap",       label: "Swap",       desc: "Trade tokens" },
          { href: "/vault",      label: "Vault",      desc: "Earn yield" },
          { href: "/lending",    label: "Lending",    desc: "Borrow & lend" },
          { href: "/governance", label: "Governance", desc: "Vote on proposals" },
        ].map(({ href, label, desc }) => (
          <Link
            key={href}
            href={href}
            className="card hover:border-brand-500/50 transition-colors cursor-pointer"
          >
            <p className="font-semibold">{label}</p>
            <p className="text-sm text-gray-400">{desc}</p>
          </Link>
        ))}
      </div>
    </div>
  );
}
