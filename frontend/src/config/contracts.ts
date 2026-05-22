// Contract addresses — populated from env vars after L2 deployment
export const ZERO_ADDRESS = "0x0000000000000000000000000000000000000000" as const;

export const ADDRESSES = {
  govToken:    (process.env.NEXT_PUBLIC_GOV_TOKEN     ?? ZERO_ADDRESS) as `0x${string}`,
  debtToken:   (process.env.NEXT_PUBLIC_DEBT_TOKEN    ?? ZERO_ADDRESS) as `0x${string}`,
  ammPool:     (process.env.NEXT_PUBLIC_AMM_POOL      ?? ZERO_ADDRESS) as `0x${string}`,
  poolFactory: (process.env.NEXT_PUBLIC_POOL_FACTORY  ?? ZERO_ADDRESS) as `0x${string}`,
  yieldVault:  (process.env.NEXT_PUBLIC_YIELD_VAULT   ?? ZERO_ADDRESS) as `0x${string}`,
  lendingPool: (process.env.NEXT_PUBLIC_LENDING_POOL  ?? ZERO_ADDRESS) as `0x${string}`,
  governor:    (process.env.NEXT_PUBLIC_GOVERNOR      ?? ZERO_ADDRESS) as `0x${string}`,
  timelock:    (process.env.NEXT_PUBLIC_TIMELOCK      ?? ZERO_ADDRESS) as `0x${string}`,
  treasury:    (process.env.NEXT_PUBLIC_TREASURY      ?? ZERO_ADDRESS) as `0x${string}`,
} as const;

export const POOL_FACTORY_ABI = [
  { type: "function", name: "getPool", inputs: [{ name: "tokenA", type: "address" }, { name: "tokenB", type: "address" }], outputs: [{ type: "address" }], stateMutability: "view" },
  { type: "function", name: "allPools", inputs: [{ name: "i", type: "uint256" }], outputs: [{ type: "address" }], stateMutability: "view" },
  { type: "function", name: "allPoolsLength", inputs: [], outputs: [{ type: "uint256" }], stateMutability: "view" },
] as const;

// ─── Minimal ABIs (only functions used by the frontend) ─────────────────────

export const ERC20_ABI = [
  { type: "function", name: "approve",   inputs: [{ name: "spender", type: "address" }, { name: "amount", type: "uint256" }], outputs: [{ type: "bool" }], stateMutability: "nonpayable" },
  { type: "function", name: "allowance", inputs: [{ name: "owner",   type: "address" }, { name: "spender", type: "address" }], outputs: [{ type: "uint256" }], stateMutability: "view" },
  { type: "function", name: "balanceOf", inputs: [{ name: "account", type: "address" }], outputs: [{ type: "uint256" }], stateMutability: "view" },
  { type: "function", name: "decimals",  inputs: [], outputs: [{ type: "uint8" }], stateMutability: "view" },
  { type: "function", name: "symbol",    inputs: [], outputs: [{ type: "string" }], stateMutability: "view" },
] as const;

export const GOV_TOKEN_ABI = [
  ...ERC20_ABI,
  { type: "function", name: "getVotes",   inputs: [{ name: "account",   type: "address" }], outputs: [{ type: "uint256" }], stateMutability: "view" },
  { type: "function", name: "delegates",  inputs: [{ name: "account",   type: "address" }], outputs: [{ type: "address" }], stateMutability: "view" },
  { type: "function", name: "delegate",   inputs: [{ name: "delegatee", type: "address" }], outputs: [], stateMutability: "nonpayable" },
  { type: "function", name: "totalSupply",inputs: [], outputs: [{ type: "uint256" }], stateMutability: "view" },
] as const;

export const AMM_POOL_ABI = [
  { type: "function", name: "token0",      inputs: [], outputs: [{ type: "address" }], stateMutability: "view" },
  { type: "function", name: "token1",      inputs: [], outputs: [{ type: "address" }], stateMutability: "view" },
  { type: "function", name: "getReserves", inputs: [], outputs: [{ name: "r0", type: "uint256" }, { name: "r1", type: "uint256" }], stateMutability: "view" },
  { type: "function", name: "getAmountOut",inputs: [{ name: "amountIn", type: "uint256" }, { name: "zeroForOne", type: "bool" }], outputs: [{ type: "uint256" }], stateMutability: "view" },
  { type: "function", name: "swapExactIn", inputs: [{ name: "zeroForOne", type: "bool" }, { name: "amountIn", type: "uint256" }, { name: "amountOutMin", type: "uint256" }, { name: "to", type: "address" }], outputs: [{ type: "uint256" }], stateMutability: "nonpayable" },
  { type: "function", name: "balanceOf",   inputs: [{ name: "account", type: "address" }], outputs: [{ type: "uint256" }], stateMutability: "view" },
] as const;

export const YIELD_VAULT_ABI = [
  { type: "function", name: "asset",          inputs: [], outputs: [{ type: "address" }], stateMutability: "view" },
  { type: "function", name: "totalAssets",    inputs: [], outputs: [{ type: "uint256" }], stateMutability: "view" },
  { type: "function", name: "totalSupply",    inputs: [], outputs: [{ type: "uint256" }], stateMutability: "view" },
  { type: "function", name: "balanceOf",      inputs: [{ name: "account", type: "address" }], outputs: [{ type: "uint256" }], stateMutability: "view" },
  { type: "function", name: "convertToAssets",inputs: [{ name: "shares", type: "uint256" }], outputs: [{ type: "uint256" }], stateMutability: "view" },
  { type: "function", name: "convertToShares",inputs: [{ name: "assets", type: "uint256" }], outputs: [{ type: "uint256" }], stateMutability: "view" },
  { type: "function", name: "previewDeposit", inputs: [{ name: "assets", type: "uint256" }], outputs: [{ type: "uint256" }], stateMutability: "view" },
  { type: "function", name: "previewRedeem",  inputs: [{ name: "shares", type: "uint256" }], outputs: [{ type: "uint256" }], stateMutability: "view" },
  { type: "function", name: "deposit",        inputs: [{ name: "assets", type: "uint256" }, { name: "receiver", type: "address" }], outputs: [{ type: "uint256" }], stateMutability: "nonpayable" },
  { type: "function", name: "redeem",         inputs: [{ name: "shares", type: "uint256" }, { name: "receiver", type: "address" }, { name: "owner", type: "address" }], outputs: [{ type: "uint256" }], stateMutability: "nonpayable" },
  { type: "function", name: "paused",         inputs: [], outputs: [{ type: "bool" }], stateMutability: "view" },
] as const;

export const LENDING_POOL_ABI = [
  { type: "function", name: "positions",      inputs: [{ name: "col", type: "address" }, { name: "debt", type: "address" }, { name: "user", type: "address" }], outputs: [{ name: "collateralAmount", type: "uint256" }, { name: "debtAmount", type: "uint256" }, { name: "debtAccruedAt", type: "uint256" }], stateMutability: "view" },
  { type: "function", name: "healthFactor",   inputs: [{ name: "col", type: "address" }, { name: "debt", type: "address" }, { name: "user", type: "address" }], outputs: [{ type: "uint256" }], stateMutability: "view" },
  { type: "function", name: "totalCollateral",inputs: [{ name: "token", type: "address" }], outputs: [{ type: "uint256" }], stateMutability: "view" },
  { type: "function", name: "totalLiquidity", inputs: [{ name: "token", type: "address" }], outputs: [{ type: "uint256" }], stateMutability: "view" },
  { type: "function", name: "totalBorrowed",  inputs: [{ name: "token", type: "address" }], outputs: [{ type: "uint256" }], stateMutability: "view" },
  { type: "function", name: "borrowRate",     inputs: [{ name: "token", type: "address" }], outputs: [{ type: "uint256" }], stateMutability: "view" },
  { type: "function", name: "borrow",         inputs: [{ name: "collateralToken", type: "address" }, { name: "collateralAmount", type: "uint256" }, { name: "debtToken", type: "address" }, { name: "borrowAmount", type: "uint256" }], outputs: [], stateMutability: "nonpayable" },
  { type: "function", name: "repay",          inputs: [{ name: "collateralToken", type: "address" }, { name: "debtToken", type: "address" }, { name: "repayAmount", type: "uint256" }], outputs: [{ type: "uint256" }], stateMutability: "nonpayable" },
] as const;

export const GOVERNOR_ABI = [
  { type: "function", name: "state",            inputs: [{ name: "proposalId", type: "uint256" }], outputs: [{ type: "uint8" }], stateMutability: "view" },
  { type: "function", name: "proposalVotes",    inputs: [{ name: "proposalId", type: "uint256" }], outputs: [{ name: "againstVotes", type: "uint256" }, { name: "forVotes", type: "uint256" }, { name: "abstainVotes", type: "uint256" }], stateMutability: "view" },
  { type: "function", name: "hasVoted",         inputs: [{ name: "proposalId", type: "uint256" }, { name: "account", type: "address" }], outputs: [{ type: "bool" }], stateMutability: "view" },
  { type: "function", name: "castVote",         inputs: [{ name: "proposalId", type: "uint256" }, { name: "support", type: "uint8" }], outputs: [{ type: "uint256" }], stateMutability: "nonpayable" },
  { type: "function", name: "castVoteWithReason",inputs: [{ name: "proposalId", type: "uint256" }, { name: "support", type: "uint8" }, { name: "reason", type: "string" }], outputs: [{ type: "uint256" }], stateMutability: "nonpayable" },
  { type: "function", name: "proposalDeadline", inputs: [{ name: "proposalId", type: "uint256" }], outputs: [{ type: "uint256" }], stateMutability: "view" },
  { type: "function", name: "votingPeriod",     inputs: [], outputs: [{ type: "uint256" }], stateMutability: "view" },
  { type: "function", name: "quorum",           inputs: [{ name: "blockNumber", type: "uint256" }], outputs: [{ type: "uint256" }], stateMutability: "view" },
  { type: "function", name: "getVotes",         inputs: [{ name: "account", type: "address" }, { name: "blockNumber", type: "uint256" }], outputs: [{ type: "uint256" }], stateMutability: "view" },
  { type: "function", name: "proposalThreshold",inputs: [], outputs: [{ type: "uint256" }], stateMutability: "view" },
  { type: "function", name: "clock",            inputs: [], outputs: [{ type: "uint48" }], stateMutability: "view" },
  {
    type: "function", name: "propose",
    inputs: [
      { name: "targets",     type: "address[]" },
      { name: "values",      type: "uint256[]" },
      { name: "calldatas",   type: "bytes[]"   },
      { name: "description", type: "string"    },
    ],
    outputs: [{ type: "uint256" }],
    stateMutability: "nonpayable",
  },
  {
    type: "event", name: "ProposalCreated",
    inputs: [
      { name: "proposalId",  type: "uint256", indexed: false },
      { name: "proposer",    type: "address", indexed: false },
      { name: "targets",     type: "address[]", indexed: false },
      { name: "values",      type: "uint256[]", indexed: false },
      { name: "signatures",  type: "string[]", indexed: false },
      { name: "calldatas",   type: "bytes[]", indexed: false },
      { name: "voteStart",   type: "uint256", indexed: false },
      { name: "voteEnd",     type: "uint256", indexed: false },
      { name: "description", type: "string", indexed: false },
    ],
  },
] as const;

export const TREASURY_ABI = [
  { type: "function", name: "releaseERC20", inputs: [
    { name: "token",  type: "address" },
    { name: "to",     type: "address" },
    { name: "amount", type: "uint256" },
  ], outputs: [], stateMutability: "nonpayable" },
  { type: "function", name: "releaseETH", inputs: [
    { name: "to",     type: "address" },
    { name: "amount", type: "uint256" },
  ], outputs: [], stateMutability: "nonpayable" },
] as const;

// ProposalState enum from OZ Governor
export const PROPOSAL_STATES = [
  "Pending", "Active", "Canceled", "Defeated",
  "Succeeded", "Queued", "Expired", "Executed",
] as const;

export type ProposalState = typeof PROPOSAL_STATES[number];

// For on-chain data: state is a uint8 (0–7)
export function proposalStateBadge(state: number): { label: string; className: string } {
  const map: Record<number, { label: string; className: string }> = {
    0: { label: "Pending",   className: "bg-yellow-100 text-yellow-800" },
    1: { label: "Active",    className: "bg-green-100  text-green-800"  },
    2: { label: "Canceled",  className: "bg-gray-100   text-gray-600"   },
    3: { label: "Defeated",  className: "bg-red-100    text-red-800"    },
    4: { label: "Succeeded", className: "bg-blue-100   text-blue-800"   },
    5: { label: "Queued",    className: "bg-purple-100 text-purple-800" },
    6: { label: "Expired",   className: "bg-gray-100   text-gray-600"   },
    7: { label: "Executed",  className: "bg-emerald-100 text-emerald-800" },
  };
  return map[state] ?? { label: "Unknown", className: "bg-gray-100 text-gray-600" };
}

// For subgraph data: state is a string ("Active", "Pending", etc.)
export function proposalStateBadgeFromString(state: string): { label: string; className: string } {
  const map: Record<string, { label: string; className: string }> = {
    Pending:   { label: "Pending",   className: "bg-yellow-100 text-yellow-800" },
    Active:    { label: "Active",    className: "bg-green-100  text-green-800"  },
    Canceled:  { label: "Canceled",  className: "bg-gray-100   text-gray-600"   },
    Defeated:  { label: "Defeated",  className: "bg-red-100    text-red-800"    },
    Succeeded: { label: "Succeeded", className: "bg-blue-100   text-blue-800"   },
    Queued:    { label: "Queued",    className: "bg-purple-100 text-purple-800" },
    Expired:   { label: "Expired",   className: "bg-gray-100   text-gray-600"   },
    Executed:  { label: "Executed",  className: "bg-emerald-100 text-emerald-800" },
  };
  return map[state] ?? { label: state, className: "bg-gray-100 text-gray-600" };
}
