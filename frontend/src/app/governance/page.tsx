"use client";

import { useEffect, useState } from "react";
import { useAccount, useReadContract, useWriteContract, useBlockNumber } from "wagmi";
import { formatEther } from "viem";
import { ADDRESSES, GOV_TOKEN_ABI, GOVERNOR_ABI, proposalStateBadge } from "@/config/contracts";
import { NetworkGuard } from "@/components/NetworkGuard";
import { TxButton } from "@/components/TxButton";
import { fetchProposals, subgraphConfigured, type SubgraphProposal } from "@/lib/subgraph";

export default function GovernancePage() {
  const { address } = useAccount();
  const { data: blockNumber } = useBlockNumber();

  // Gov token state
  const { data: govBalance } = useReadContract({
    address: ADDRESSES.govToken, abi: GOV_TOKEN_ABI, functionName: "balanceOf",
    args: [address ?? "0x0000000000000000000000000000000000000000"],
    query: { enabled: !!address },
  });
  const { data: votingPower, refetch: refetchVotes } = useReadContract({
    address: ADDRESSES.govToken, abi: GOV_TOKEN_ABI, functionName: "getVotes",
    args: [address ?? "0x0000000000000000000000000000000000000000"],
    query: { enabled: !!address },
  });
  const { data: delegatee, refetch: refetchDelegate } = useReadContract({
    address: ADDRESSES.govToken, abi: GOV_TOKEN_ABI, functionName: "delegates",
    args: [address ?? "0x0000000000000000000000000000000000000000"],
    query: { enabled: !!address },
  });

  const { writeContractAsync } = useWriteContract();

  // Delegate to self
  const handleDelegateSelf = async () => {
    if (!address) throw new Error("Not connected");
    await writeContractAsync({
      address: ADDRESSES.govToken, abi: GOV_TOKEN_ABI,
      functionName: "delegate", args: [address],
    });
    await Promise.all([refetchVotes(), refetchDelegate()]);
  };

  const isSelfDelegated = delegatee?.toString().toLowerCase() === address?.toLowerCase();

  // ─── Proposals from subgraph ────────────────────────────────────────────────
  const [proposals, setProposals] = useState<SubgraphProposal[]>([]);
  const [loading, setLoading] = useState(false);

  useEffect(() => {
    if (!subgraphConfigured) return;
    setLoading(true);
    fetchProposals(20).then((data) => {
      setProposals(data);
      setLoading(false);
    });
  }, []);

  const fmt = (v: bigint | undefined, dec = 2) =>
    v !== undefined ? Number(formatEther(v)).toFixed(dec) : "—";

  const shortAddr = (a: string) => `${a.slice(0, 6)}…${a.slice(-4)}`;

  return (
    <NetworkGuard>
      <div className="space-y-8">
        <h1 className="text-2xl font-bold">Governance</h1>

        {/* Voting Power Card */}
        <div className="card space-y-4">
          <h2 className="font-semibold">Your Voting Power</h2>
          <div className="grid grid-cols-2 gap-4 text-sm">
            <div>
              <p className="label">DGT Balance</p>
              <p className="text-xl font-mono">{fmt(govBalance as bigint)}</p>
            </div>
            <div>
              <p className="label">Voting Power</p>
              <p className="text-xl font-mono">{fmt(votingPower as bigint)}</p>
            </div>
          </div>
          <div className="text-sm">
            <p className="label">Delegating To</p>
            <p className="font-mono text-gray-300">
              {delegatee ? (isSelfDelegated ? "Self" : shortAddr(delegatee as string)) : "—"}
            </p>
          </div>
          {!isSelfDelegated && (
            <TxButton
              label="Delegate to Self"
              loadingLabel="Delegating..."
              onClick={handleDelegateSelf}
              variant="secondary"
            />
          )}
        </div>

        {/* Proposals */}
        <div className="space-y-4">
          <div className="flex items-center justify-between">
            <h2 className="font-semibold text-lg">Proposals</h2>
            {subgraphConfigured && (
              <span className="text-xs text-green-400 bg-green-950/50 px-2 py-1 rounded-full">
                Live from The Graph
              </span>
            )}
          </div>

          {!subgraphConfigured && (
            <div className="card border-yellow-800/50 bg-yellow-950/20">
              <p className="text-yellow-400 font-medium text-sm">Subgraph not configured</p>
              <p className="text-gray-400 text-sm mt-1">
                Set <code className="text-yellow-300">NEXT_PUBLIC_SUBGRAPH_URL</code> in{" "}
                <code className="text-gray-300">.env.local</code> after deploying your subgraph
                to The Graph Studio. Below are on-chain proposal IDs you can paste in for testing.
              </p>
            </div>
          )}

          {loading && (
            <div className="card text-center text-gray-400 py-8">Loading proposals…</div>
          )}

          {subgraphConfigured && !loading && proposals.length === 0 && (
            <div className="card text-center text-gray-400 py-8">
              No proposals found in the subgraph yet.
            </div>
          )}

          {proposals.map((p) => (
            <ProposalCard key={p.id} proposal={p} address={address} writeContractAsync={writeContractAsync} />
          ))}

          {/* On-chain fallback: manual proposal ID lookup */}
          <OnChainProposal address={address} writeContractAsync={writeContractAsync} />
        </div>
      </div>
    </NetworkGuard>
  );
}

// ─── Subgraph Proposal Card ───────────────────────────────────────────────────

function ProposalCard({
  proposal,
  address,
  writeContractAsync,
}: {
  proposal: SubgraphProposal;
  address: `0x${string}` | undefined;
  writeContractAsync: ReturnType<typeof useWriteContract>["writeContractAsync"];
}) {
  const proposalId = BigInt(proposal.proposalId);
  const badge = proposalStateBadge(parseInt(proposal.state));

  const { data: hasVoted, refetch } = useReadContract({
    address: ADDRESSES.governor, abi: GOVERNOR_ABI, functionName: "hasVoted",
    args: [proposalId, address ?? "0x0000000000000000000000000000000000000000"],
    query: { enabled: !!address },
  });

  const vote = (support: 0 | 1 | 2) => async () => {
    if (!address) throw new Error("Not connected");
    await writeContractAsync({
      address: ADDRESSES.governor, abi: GOVERNOR_ABI,
      functionName: "castVote", args: [proposalId, support],
    });
    await refetch();
  };

  const isActive = proposal.state === "1";

  const forVotes     = Number(formatEther(BigInt(proposal.forVotes))).toFixed(0);
  const againstVotes = Number(formatEther(BigInt(proposal.againstVotes))).toFixed(0);

  const title = proposal.description.split("\n")[0].replace(/^#+\s*/, "").slice(0, 80);

  return (
    <div className="card space-y-3">
      <div className="flex items-start justify-between gap-3">
        <p className="font-medium">{title || `Proposal #${proposal.proposalId.slice(-6)}`}</p>
        <span className={`text-xs px-2 py-1 rounded-full whitespace-nowrap ${badge.className}`}>
          {badge.label}
        </span>
      </div>

      <div className="flex gap-6 text-sm text-gray-400">
        <span>For: <span className="text-green-400 font-mono">{forVotes}</span></span>
        <span>Against: <span className="text-red-400 font-mono">{againstVotes}</span></span>
      </div>

      {isActive && !hasVoted && (
        <div className="flex gap-2">
          <TxButton label="Vote For" loadingLabel="Voting..." onClick={vote(1)} />
          <TxButton label="Against"  loadingLabel="Voting..." onClick={vote(0)} variant="secondary" />
          <TxButton label="Abstain"  loadingLabel="Voting..." onClick={vote(2)} variant="secondary" />
        </div>
      )}
      {hasVoted && <p className="text-sm text-gray-500 italic">You have already voted.</p>}
    </div>
  );
}

// ─── On-chain fallback: look up proposal by ID ────────────────────────────────

function OnChainProposal({
  address,
  writeContractAsync,
}: {
  address: `0x${string}` | undefined;
  writeContractAsync: ReturnType<typeof useWriteContract>["writeContractAsync"];
}) {
  const [id, setId] = useState("");
  const [lookupId, setLookupId] = useState<bigint | null>(null);

  const { data: state } = useReadContract({
    address: ADDRESSES.governor, abi: GOVERNOR_ABI, functionName: "state",
    args: [lookupId ?? 0n],
    query: { enabled: lookupId !== null },
  });
  const { data: votes } = useReadContract({
    address: ADDRESSES.governor, abi: GOVERNOR_ABI, functionName: "proposalVotes",
    args: [lookupId ?? 0n],
    query: { enabled: lookupId !== null },
  });
  const { data: hasVoted, refetch } = useReadContract({
    address: ADDRESSES.governor, abi: GOVERNOR_ABI, functionName: "hasVoted",
    args: [lookupId ?? 0n, address ?? "0x0000000000000000000000000000000000000000"],
    query: { enabled: lookupId !== null && !!address },
  });

  const voteArr = votes as [bigint, bigint, bigint] | undefined;
  const stateNum = state as number | undefined;
  const badge = stateNum !== undefined ? proposalStateBadge(stateNum) : null;
  const isActive = stateNum === 1;

  const vote = (support: 0 | 1 | 2) => async () => {
    if (!address || !lookupId) throw new Error("Not ready");
    await writeContractAsync({
      address: ADDRESSES.governor, abi: GOVERNOR_ABI,
      functionName: "castVote", args: [lookupId, support],
    });
    await refetch();
  };

  return (
    <div className="card space-y-4">
      <h3 className="font-medium text-sm text-gray-400 uppercase tracking-wider">
        Look Up Proposal On-Chain
      </h3>
      <div className="flex gap-2">
        <input
          className="input flex-1"
          placeholder="Proposal ID (uint256)"
          value={id}
          onChange={(e) => setId(e.target.value)}
        />
        <button
          className="btn-secondary w-auto px-4"
          onClick={() => {
            try { setLookupId(BigInt(id)); } catch { /* ignore */ }
          }}
        >
          Look Up
        </button>
      </div>

      {lookupId !== null && badge && (
        <div className="space-y-3">
          <div className="flex items-center gap-3">
            <span className={`text-xs px-2 py-1 rounded-full ${badge.className}`}>{badge.label}</span>
          </div>
          {voteArr && (
            <div className="flex gap-6 text-sm text-gray-400">
              <span>For: <span className="text-green-400 font-mono">{Number(formatEther(voteArr[1])).toFixed(0)}</span></span>
              <span>Against: <span className="text-red-400 font-mono">{Number(formatEther(voteArr[0])).toFixed(0)}</span></span>
              <span>Abstain: <span className="font-mono">{Number(formatEther(voteArr[2])).toFixed(0)}</span></span>
            </div>
          )}
          {isActive && !hasVoted && (
            <div className="flex gap-2">
              <TxButton label="Vote For" loadingLabel="Voting..." onClick={vote(1)} />
              <TxButton label="Against"  loadingLabel="Voting..." onClick={vote(0)} variant="secondary" />
              <TxButton label="Abstain"  loadingLabel="Voting..." onClick={vote(2)} variant="secondary" />
            </div>
          )}
          {hasVoted && <p className="text-sm text-gray-500 italic">Already voted.</p>}
        </div>
      )}
    </div>
  );
}
