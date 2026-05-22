"use client";

import { useEffect, useState } from "react";
import { useAccount, usePublicClient, useReadContract, useWriteContract } from "wagmi";
import { decodeEventLog, encodeFunctionData, formatEther, isAddress, isHex, parseEther } from "viem";
import { ADDRESSES, GOV_TOKEN_ABI, GOVERNOR_ABI, TREASURY_ABI, proposalStateBadge, proposalStateBadgeFromString } from "@/config/contracts";
import { NetworkGuard } from "@/components/NetworkGuard";
import { TxButton } from "@/components/TxButton";
import { fetchProposals, subgraphConfigured, type SubgraphProposal } from "@/lib/subgraph";

export default function GovernancePage() {
  const { address } = useAccount();

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
  const { data: proposalThreshold } = useReadContract({
    address: ADDRESSES.governor, abi: GOVERNOR_ABI, functionName: "proposalThreshold",
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
  const [reloadKey, setReloadKey] = useState(0);

  useEffect(() => {
    if (!subgraphConfigured) return;
    setLoading(true);
    fetchProposals(20).then((data) => {
      setProposals(data);
      setLoading(false);
    });
  }, [reloadKey]);

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

        {/* Create Proposal */}
        <CreateProposalForm
          address={address}
          votingPower={votingPower as bigint | undefined}
          proposalThreshold={proposalThreshold as bigint | undefined}
          isSelfDelegated={isSelfDelegated}
          writeContractAsync={writeContractAsync}
          onCreated={() => setReloadKey((k) => k + 1)}
        />

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
  const badge = proposalStateBadgeFromString(proposal.state);

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

  const isActive = proposal.state === "Active";

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

// ─── Create Proposal Form ─────────────────────────────────────────────────────

type ActionKind = "signaling" | "treasuryERC20" | "custom";

function CreateProposalForm({
  address,
  votingPower,
  proposalThreshold,
  isSelfDelegated,
  writeContractAsync,
  onCreated,
}: {
  address: `0x${string}` | undefined;
  votingPower: bigint | undefined;
  proposalThreshold: bigint | undefined;
  isSelfDelegated: boolean;
  writeContractAsync: ReturnType<typeof useWriteContract>["writeContractAsync"];
  onCreated: () => void;
}) {
  const publicClient = usePublicClient();
  const [kind, setKind] = useState<ActionKind>("signaling");
  const [description, setDescription] = useState("");
  const [lastProposalId, setLastProposalId] = useState<string | null>(null);
  const [lastTxHash, setLastTxHash] = useState<string | null>(null);

  // Treasury releaseERC20 fields
  const [tToken, setTToken]       = useState<string>(ADDRESSES.govToken);
  const [tRecipient, setTRecipient] = useState<string>("");
  const [tAmount, setTAmount]     = useState<string>("");

  // Custom raw call fields
  const [cTarget, setCTarget]     = useState<string>("");
  const [cValue, setCValue]       = useState<string>("0");
  const [cCalldata, setCCalldata] = useState<string>("0x");

  const hasThreshold =
    votingPower !== undefined &&
    proposalThreshold !== undefined &&
    votingPower >= proposalThreshold;

  const submit = async () => {
    if (!address) throw new Error("Connect wallet first.");
    if (!isSelfDelegated) throw new Error("Delegate to self first to activate voting power.");
    if (!description.trim()) throw new Error("Description is required.");

    let targets:   `0x${string}`[] = [];
    let values:    bigint[]        = [];
    let calldatas: `0x${string}`[] = [];

    if (kind === "signaling") {
      // No-op: call our own EOA with empty calldata + 0 value. Always succeeds.
      targets   = [address];
      values    = [0n];
      calldatas = ["0x"];
    } else if (kind === "treasuryERC20") {
      if (ADDRESSES.treasury === "0x0000000000000000000000000000000000000000") {
        throw new Error("NEXT_PUBLIC_TREASURY is not set in .env.local.");
      }
      if (!isAddress(tToken))     throw new Error("Invalid token address.");
      if (!isAddress(tRecipient)) throw new Error("Invalid recipient address.");
      if (!tAmount)               throw new Error("Amount is required.");
      const amountWei = parseEther(tAmount);
      const data = encodeFunctionData({
        abi: TREASURY_ABI,
        functionName: "releaseERC20",
        args: [tToken as `0x${string}`, tRecipient as `0x${string}`, amountWei],
      });
      targets   = [ADDRESSES.treasury];
      values    = [0n];
      calldatas = [data];
    } else {
      if (!isAddress(cTarget))   throw new Error("Invalid target address.");
      if (!isHex(cCalldata))     throw new Error("Calldata must be hex (0x…).");
      let valueWei = 0n;
      try { valueWei = cValue ? parseEther(cValue) : 0n; }
      catch { throw new Error("Invalid ETH value."); }
      targets   = [cTarget as `0x${string}`];
      values    = [valueWei];
      calldatas = [cCalldata as `0x${string}`];
    }

    const hash = await writeContractAsync({
      address: ADDRESSES.governor,
      abi: GOVERNOR_ABI,
      functionName: "propose",
      args: [targets, values, calldatas, description],
    });
    setLastTxHash(hash);
    setLastProposalId(null);

    // Pull proposalId out of the ProposalCreated event in the tx receipt so the
    // user can paste it into "Look Up Proposal On-Chain" immediately, without
    // hunting through the block explorer.
    if (publicClient) {
      try {
        const receipt = await publicClient.waitForTransactionReceipt({ hash });
        for (const log of receipt.logs) {
          if (log.address.toLowerCase() !== ADDRESSES.governor.toLowerCase()) continue;
          try {
            const decoded = decodeEventLog({
              abi: GOVERNOR_ABI,
              data: log.data,
              topics: log.topics,
            });
            if (decoded.eventName === "ProposalCreated") {
              const args = decoded.args as { proposalId: bigint };
              setLastProposalId(args.proposalId.toString());
              break;
            }
          } catch { /* not a ProposalCreated log */ }
        }
      } catch { /* receipt fetch failed — UI just won't show the id */ }
    }

    setDescription("");
    // Give the subgraph a few seconds to index the event, then refetch.
    setTimeout(onCreated, 5000);
  };

  const thresholdFmt =
    proposalThreshold !== undefined
      ? Number(formatEther(proposalThreshold)).toFixed(0)
      : "—";

  return (
    <div className="card space-y-4">
      <div className="flex items-start justify-between gap-3">
        <h2 className="font-semibold">Create Proposal</h2>
        <span className="text-xs text-gray-400">
          Threshold: <span className="font-mono text-gray-300">{thresholdFmt} DGT</span>
        </span>
      </div>

      {!address && (
        <p className="text-sm text-yellow-400">Connect your wallet to create a proposal.</p>
      )}
      {address && !isSelfDelegated && (
        <p className="text-sm text-yellow-400">
          You need to delegate voting power to yourself before you can propose.
        </p>
      )}
      {address && isSelfDelegated && !hasThreshold && (
        <p className="text-sm text-yellow-400">
          You hold less than the {thresholdFmt} DGT proposal threshold — propose() will revert.
        </p>
      )}

      <div>
        <p className="label">Action</p>
        <select
          className="input"
          value={kind}
          onChange={(e) => setKind(e.target.value as ActionKind)}
        >
          <option value="signaling">Signaling (no-op test call)</option>
          <option value="treasuryERC20">Treasury — release ERC20</option>
          <option value="custom">Custom raw call</option>
        </select>
        <p className="text-xs text-gray-500 mt-1">
          {kind === "signaling" &&
            "Sends a 0-value call to your own address with empty calldata. Useful to test the proposal lifecycle without changing state."}
          {kind === "treasuryERC20" &&
            "Encodes Treasury.releaseERC20(token, to, amount). The Timelock holds SPENDER_ROLE on the Treasury — this is the canonical DAO payout."}
          {kind === "custom" &&
            "Single (target, value, calldata) tuple. Encode the inner call yourself (e.g. via cast calldata or viem)."}
        </p>
      </div>

      {kind === "treasuryERC20" && (
        <div className="space-y-3">
          <div>
            <p className="label">Token address</p>
            <input
              className="input font-mono text-sm"
              placeholder="0x… ERC20 token"
              value={tToken}
              onChange={(e) => setTToken(e.target.value)}
            />
          </div>
          <div>
            <p className="label">Recipient</p>
            <input
              className="input font-mono text-sm"
              placeholder="0x… recipient address"
              value={tRecipient}
              onChange={(e) => setTRecipient(e.target.value)}
            />
          </div>
          <div>
            <p className="label">Amount (token units, 18 decimals)</p>
            <input
              className="input font-mono text-sm"
              placeholder="1000"
              value={tAmount}
              onChange={(e) => setTAmount(e.target.value)}
            />
          </div>
        </div>
      )}

      {kind === "custom" && (
        <div className="space-y-3">
          <div>
            <p className="label">Target</p>
            <input
              className="input font-mono text-sm"
              placeholder="0x… contract to call"
              value={cTarget}
              onChange={(e) => setCTarget(e.target.value)}
            />
          </div>
          <div>
            <p className="label">ETH value (wei expressed in ether)</p>
            <input
              className="input font-mono text-sm"
              placeholder="0"
              value={cValue}
              onChange={(e) => setCValue(e.target.value)}
            />
          </div>
          <div>
            <p className="label">Calldata (hex)</p>
            <input
              className="input font-mono text-sm"
              placeholder="0x"
              value={cCalldata}
              onChange={(e) => setCCalldata(e.target.value)}
            />
          </div>
        </div>
      )}

      <div>
        <p className="label">Description (first line is the proposal title)</p>
        <textarea
          className="input min-h-[100px]"
          placeholder={"# Increase staking rewards\n\nDetails…"}
          value={description}
          onChange={(e) => setDescription(e.target.value)}
        />
      </div>

      <TxButton
        label="Submit Proposal"
        loadingLabel="Submitting..."
        onClick={submit}
        disabled={!address || !isSelfDelegated}
      />

      {lastProposalId && (
        <div className="bg-green-950/30 border border-green-900/50 rounded-xl p-3 space-y-2 text-sm">
          <p className="text-green-400 font-medium">Proposal created!</p>
          <div>
            <p className="label text-xs">Proposal ID (paste into "Look Up Proposal On-Chain" below)</p>
            <div className="flex gap-2 items-center">
              <code className="font-mono text-xs text-gray-200 break-all flex-1 bg-gray-900/60 px-2 py-1 rounded">
                {lastProposalId}
              </code>
              <button
                className="btn-secondary w-auto px-3 py-1 text-xs"
                onClick={() => navigator.clipboard.writeText(lastProposalId)}
              >
                Copy
              </button>
            </div>
          </div>
          {lastTxHash && (
            <p className="text-xs text-gray-400">
              tx:{" "}
              <a
                href={`https://sepolia-optimism.etherscan.io/tx/${lastTxHash}`}
                target="_blank"
                rel="noreferrer"
                className="font-mono text-brand-400 hover:underline"
              >
                {lastTxHash.slice(0, 10)}…{lastTxHash.slice(-8)}
              </a>
            </p>
          )}
        </div>
      )}
    </div>
  );
}
