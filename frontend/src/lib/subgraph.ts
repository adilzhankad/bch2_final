import { GraphQLClient, gql } from "graphql-request";

const url = process.env.NEXT_PUBLIC_SUBGRAPH_URL ?? "";

export const subgraphConfigured = url.length > 0 && !url.includes("YOUR_ID");

const client = subgraphConfigured ? new GraphQLClient(url) : null;

// ─── Types ────────────────────────────────────────────────────────────────────

export type SubgraphProposal = {
  id: string;
  proposalId: string;
  proposer: string;
  description: string;
  voteStart: string;
  voteEnd: string;
  forVotes: string;
  againstVotes: string;
  abstainVotes: string;
  state: string;
};

export type SubgraphSwap = {
  id: string;
  sender: string;
  amountIn: string;
  amountOut: string;
  timestamp: string;
};

export type SubgraphDeposit = {
  id: string;
  caller: string;
  assets: string;
  shares: string;
  timestamp: string;
};

// ─── Queries ──────────────────────────────────────────────────────────────────

// Query 1: Active proposals
const PROPOSALS_QUERY = gql`
  query GetProposals($first: Int!, $state: String) {
    proposals(
      first: $first
      orderBy: voteStart
      orderDirection: desc
      where: { state: $state }
    ) {
      id
      proposalId
      proposer
      description
      voteStart
      voteEnd
      forVotes
      againstVotes
      abstainVotes
      state
    }
  }
`;

// Query 2: All proposals (for listing)
const ALL_PROPOSALS_QUERY = gql`
  query GetAllProposals($first: Int!) {
    proposals(first: $first, orderBy: voteStart, orderDirection: desc) {
      id
      proposalId
      proposer
      description
      voteStart
      voteEnd
      forVotes
      againstVotes
      abstainVotes
      state
    }
  }
`;

// Query 3: Recent swaps
const SWAPS_QUERY = gql`
  query GetSwaps($first: Int!) {
    swaps(first: $first, orderBy: timestamp, orderDirection: desc) {
      id
      sender
      amountIn
      amountOut
      timestamp
    }
  }
`;

// Query 4: Recent vault deposits
const DEPOSITS_QUERY = gql`
  query GetDeposits($first: Int!) {
    deposits(first: $first, orderBy: timestamp, orderDirection: desc) {
      id
      caller
      assets
      shares
      timestamp
    }
  }
`;

// Query 5: Protocol stats
const STATS_QUERY = gql`
  query GetProtocolStats {
    protocolStats(id: "global") {
      totalSwaps
      totalVolumeUSD
      totalVaultDeposits
      totalVaultTVL
    }
  }
`;

// ─── Fetchers ─────────────────────────────────────────────────────────────────

export async function fetchProposals(first = 20): Promise<SubgraphProposal[]> {
  if (!client) return [];
  try {
    const data = await client.request<{ proposals: SubgraphProposal[] }>(
      ALL_PROPOSALS_QUERY,
      { first }
    );
    return data.proposals;
  } catch {
    return [];
  }
}

export async function fetchActiveProposals(): Promise<SubgraphProposal[]> {
  if (!client) return [];
  try {
    const data = await client.request<{ proposals: SubgraphProposal[] }>(
      PROPOSALS_QUERY,
      { first: 10, state: "Active" }
    );
    return data.proposals;
  } catch {
    return [];
  }
}

export async function fetchRecentSwaps(first = 10): Promise<SubgraphSwap[]> {
  if (!client) return [];
  try {
    const data = await client.request<{ swaps: SubgraphSwap[] }>(
      SWAPS_QUERY,
      { first }
    );
    return data.swaps;
  } catch {
    return [];
  }
}

export async function fetchRecentDeposits(first = 10): Promise<SubgraphDeposit[]> {
  if (!client) return [];
  try {
    const data = await client.request<{ deposits: SubgraphDeposit[] }>(
      DEPOSITS_QUERY,
      { first }
    );
    return data.deposits;
  } catch {
    return [];
  }
}

export async function fetchProtocolStats() {
  if (!client) return null;
  try {
    const data = await client.request<{ protocolStats: Record<string, string> }>(
      STATS_QUERY
    );
    return data.protocolStats;
  } catch {
    return null;
  }
}
