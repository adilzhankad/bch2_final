"use client";

import { useAccount, useChainId, useSwitchChain } from "wagmi";
import { TARGET_CHAIN } from "@/config/wagmi";

export function NetworkGuard({ children }: { children: React.ReactNode }) {
  const { isConnected } = useAccount();
  const chainId = useChainId();
  const { switchChain } = useSwitchChain();

  if (!isConnected) {
    return (
      <div className="card text-center py-16">
        <p className="text-2xl mb-2">Connect Wallet</p>
        <p className="text-gray-400">Connect your wallet to use the protocol.</p>
      </div>
    );
  }

  if (chainId !== TARGET_CHAIN.id) {
    return (
      <div className="card text-center py-16 space-y-4">
        <p className="text-xl text-yellow-400">Wrong Network</p>
        <p className="text-gray-400">
          Please switch to <span className="text-white font-medium">{TARGET_CHAIN.name}</span>.
        </p>
        <button
          className="btn-primary max-w-xs mx-auto"
          onClick={() => switchChain({ chainId: TARGET_CHAIN.id })}
        >
          Switch to {TARGET_CHAIN.name}
        </button>
      </div>
    );
  }

  return <>{children}</>;
}
