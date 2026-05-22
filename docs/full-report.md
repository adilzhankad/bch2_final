---
title: "DeFi Super-App — Architecture, Security Audit & Gas Report"
author: "Adilzhan Kadyrov, Dastan Bekesh"
date: "2026-05-18"
---

# Part I — Architecture & Design Document

## 1. Executive Summary

The DeFi Super-App is a production-grade decentralized protocol implementing
the **Option A** scenario from the project specification: an automated market
maker (AMM), an over-collateralized lending pool, an ERC-4626 tokenized yield
vault, a full DAO governance stack on top of an ERC-20 voting token, a
Chainlink price-feed integration with staleness protection, a Graph subgraph
indexing every protocol event, and a Next.js frontend that wires it all to
end users on Optimism Sepolia.

The system is composed of eleven Solidity source files (~1,400 lines), two
of which are upgradeable via UUPS proxies (`GovTokenV1/V2` and
`YieldVaultV1/V2`). Privileged operations are concentrated behind a single
`TimelockController` with a 2-day delay; the deployer EOA holds **no
permanent roles** anywhere after the post-deployment handoff script runs.
A complete propose → vote → queue → execute lifecycle is covered by
integration tests, and the post-deployment state is verified by a dedicated
script whose output is checked into the repository.

## 2. System Context (C4 Level 1)

```
                ┌──────────────────────────┐
                │  End user (browser)      │
                │  • MetaMask / WC wallet  │
                │  • Frontend dApp         │
                └────────────┬─────────────┘
                             │ JSON-RPC + EIP-1193
                             ▼
                ┌──────────────────────────┐
                │  Optimism Sepolia (L2)   │
                │  ┌────────────────────┐  │
                │  │  DeFi Super-App    │  │
                │  │  (this protocol)   │  │
                │  └─────────┬──────────┘  │
                └────────────┼─────────────┘
                             │
              ┌──────────────┼─────────────┐
              ▼              ▼             ▼
   ┌──────────────┐ ┌────────────────┐ ┌───────────────┐
   │  Chainlink   │ │  The Graph     │ │  L2 bridge /  │
   │  AggregatorV3│ │  Subgraph      │ │  Etherscan    │
   │  (price feed)│ │  (event index) │ │  (verify)     │
   └──────────────┘ └────────────────┘ └───────────────┘
```

**External boundaries:**

| Boundary | Direction | Trust assumption |
|---|---|---|
| Chainlink AggregatorV3 | Read | Honest, may lag — staleness guard rejects feeds older than `N` seconds. |
| The Graph indexer | Read | Eventually consistent; never used for value transfer, only for UI. |
| L2 sequencer | Bidirectional | Standard rollup trust — Optimism Sepolia inherits Ethereum security. |
| End-user wallet | Sign | User is responsible for key safety; protocol enforces all auth on-chain. |

## 3. Container Diagram

```
┌──────────────────────── Governance Layer ────────────────────────┐
│                                                                  │
│    GovTokenV1/V2  ──delegates──►  DeFiGovernor                   │
│    (ERC20Votes +                  (1d delay, 7d period,          │
│     ERC20Permit,                   4% quorum, 1% threshold)      │
│     UUPS)                              │                         │
│                                        ▼                         │
│                                TimelockController                │
│                                (2-day delay)                     │
│                                  │   │                           │
│                  ┌───────────────┘   └───────────────┐           │
│                  │                                   │           │
│                  ▼                                   ▼           │
│          Treasury (ETH + ERC-20)              admin role over    │
│          (SPENDER_ROLE = Timelock)            every contract     │
│                                                                  │
└──────────────────────────────────────────────────────────────────┘
                                  │
                                  ▼
┌──────────────────────── Protocol Layer ──────────────────────────┐
│                                                                  │
│  PoolFactory  ─CREATE / CREATE2─►  AMMPool (x·y=k, 0.3% fee)     │
│  (Ownable)                          │                            │
│                                     │                            │
│  LendingPool  ◄──getPrice──── PriceOracle  ◄── Chainlink         │
│  (AccessControl,                                                 │
│   ReentrancyGuard)                                               │
│                                                                  │
│  YieldVaultV1/V2 (ERC-4626, UUPS, Pausable)                      │
│                                                                  │
│  ProtocolNFT (ERC-721, AccessControl)                            │
│                                                                  │
└──────────────────────────────────────────────────────────────────┘
                                  │
                                  ▼
┌──────────────────────── Indexer Layer ───────────────────────────┐
│                                                                  │
│  The Graph subgraph (15 entities, 7 mappings)                    │
│  ├─ ammPool.ts          (Swap, LiquidityEvent)                   │
│  ├─ lendingPool.ts      (Deposit, Borrow, Repay, Liquidation)    │
│  ├─ yieldVault.ts       (Deposit, Withdrawal, YieldInjection)    │
│  ├─ governor.ts         (Proposal, Vote)                         │
│  ├─ protocolNft.ts      (NFTMint)                                │
│  └─ poolFactory.ts      (PoolCreated)                            │
│                                                                  │
└──────────────────────────────────────────────────────────────────┘
```

**Roles cheat-sheet (after `Deploy.s.sol::_handoffToTimelock`):**

| Contract | Role | Holder |
|---|---|---|
| GovToken | DEFAULT_ADMIN_ROLE, MINTER_ROLE, UPGRADER_ROLE | TimelockController |
| ProtocolNFT | DEFAULT_ADMIN_ROLE, MINTER_ROLE | TimelockController |
| LendingPool | DEFAULT_ADMIN_ROLE, MANAGER_ROLE | TimelockController |
| YieldVault | DEFAULT_ADMIN_ROLE, PAUSER_ROLE, YIELD_MANAGER_ROLE, UPGRADER_ROLE | TimelockController |
| Treasury | DEFAULT_ADMIN_ROLE, SPENDER_ROLE | TimelockController |
| TimelockController | PROPOSER_ROLE, CANCELLER_ROLE | DeFiGovernor |
| TimelockController | EXECUTOR_ROLE | `address(0)` (any wallet may execute) |
| PoolFactory (Ownable) | owner | TimelockController |
| Mock USDC (Ownable) | owner | TimelockController |

**Critical property:** the deployer EOA has no role on any contract once
deployment finishes — verified in CI by `test/DeployVerify.t.sol` and at
runtime by `script/Verify.s.sol`.

## 4. Sequence Diagrams — 3 critical flows

### 4.1 Swap (AMM)

```
User           Wallet         ERC-20A        AMMPool        ERC-20B
 │   approve()    │              │              │              │
 ├───────────────►│              │              │              │
 │                ├─approve──────►              │              │
 │                │              │              │              │
 │  swapExactIn   │              │              │              │
 ├───────────────►│              │              │              │
 │                ├─swapExactIn──────────────►  │              │
 │                │              │transferFrom │              │
 │                │              ◄─────────────┤              │
 │                │              │              │ transfer    │
 │                │              │              ├─────────────►
 │                │              │              │              │
 │                │              │  (k must not decrease)      │
 │                │              │              │              │
 │                ◄────────────────success──────┤              │
```

Critical invariant `r0 * r1 >= k_prev` is asserted in
`invariant_k_never_decreases` over 1,024 calls — never violated.

### 4.2 Propose → Vote → Queue → Execute

```
Proposer       Governor      Token        Timelock      Target
   │  propose(…)  │            │              │            │
   ├─────────────►│  snapshot  │              │            │
   │              ├───────────►│              │            │
   │              │            │              │            │
   │              │  ◄── voting delay (1 day) ──           │
   │              │                                        │
   │  castVote    │                                        │
   ├─────────────►│  countVotes                            │
   │              │                                        │
   │              │  ◄── voting period (7 days) ──         │
   │              │                                        │
   │  queue(…)    │            │              │            │
   ├─────────────►├─schedule───────────────────►            │
   │              │                                        │
   │              │  ◄── timelock delay (2 days) ──        │
   │              │                                        │
   │  execute(…)  │            │              │            │
   ├─────────────►├─execute────────────────────►execute──► │
   │              │            │              │            │
```

All four states (Pending → Active → Succeeded → Queued → Executed) are
covered end-to-end in `test_fullGovernanceCycle`.

### 4.3 Borrow → Health-factor drop → Liquidation

```
Borrower       LendingPool      Oracle           Liquidator
   │  borrow(coll, amt)               │                 │
   ├───────────────────►              │                 │
   │             ├──getPrice──────────►                 │
   │             │  ◄── staleness check ──              │
   │             │                                      │
   │             │ collateralValue >= debt * 1/LTV ✓    │
   │             ◄──debt token────────                  │
   │                                                    │
   │  ── (price drops) ──             │                 │
   │             ├──getPrice──────────►                 │
   │             │  hf = (coll * priceColl * LTV) /     │
   │             │       (debt * priceDebt) < 1.0 ✗     │
   │                                                    │
   │             │            liquidate(…)              │
   │             │  ◄─────────────────────────────────  │
   │             │ seizes collateral + 5% bonus         │
   │             │ updates totalCollateral              │
   │             ├─transfer coll + bonus ──────────────►
```

Tested by `test_liquidate_succeeds` and the partial-repay /
proportional-return invariant `test_repay_partial_health_factor_preserved`.

## 5. Storage Layouts

**`GovTokenV1` (upgradeable).** Inherits from `ERC20Upgradeable`,
`ERC20PermitUpgradeable`, `ERC20VotesUpgradeable`, `AccessControlUpgradeable`,
`UUPSUpgradeable`. OpenZeppelin v5 uses the **namespaced storage** layout
(EIP-7201) for all `Upgradeable` parents, so each parent owns an isolated
slot keyed by a unique constant. `GovTokenV2` adds no new state, only a
pure-function `version()` and a constant — collision impossible by
construction.

**`YieldVaultV1` (upgradeable).** Inherits `ERC20Upgradeable`,
`ERC4626Upgradeable`, `PausableUpgradeable`, `AccessControlUpgradeable`,
`UUPSUpgradeable`. Same EIP-7201 isolation. `YieldVaultV2` appends two
storage variables — `uint256 performanceFee` and `address feeRecipient` —
at the end of the inheritance chain, after all parent namespaces. Because
EIP-7201 isolates parent state, the new V2 slots cannot collide with V1.

**Non-upgradeable contracts** (`AMMPool`, `LendingPool`, `PoolFactory`,
`PriceOracle`, `Treasury`, `ProtocolNFT`) use vanilla storage; no proxy
layout concerns.

## 6. Trust Assumptions

| Actor | Powers | Mitigation |
|---|---|---|
| Token holder | Vote, propose if ≥ 1% of supply | Quorum 4% + 7-day voting period limits flash-loan governance attacks. |
| DeFiGovernor | Schedule operations on Timelock | Can only schedule — every action waits 2 days. |
| TimelockController | Execute any privileged call protocol-wide | Holders are revoked at deploy; only Governor can schedule. |
| Anonymous executor | Execute already-queued proposals after delay | Cannot create proposals; cannot cancel; cannot schedule. |
| Chainlink feed | Reports price | Staleness threshold rejects feeds older than N s; negative/zero answer rejected. |
| Deployer EOA | None after handoff | Verified by `DeployVerifyTest` in CI on every push. |

**Worst-case multisig compromise:** there is no multisig in the system —
the only standing privileged account is the `TimelockController` itself.
A compromise of all key holders would require corrupting the entire
quorum (4% of voting supply) AND waiting 2 days for the timelock to
release the malicious call. Honest holders observe the queued operation
in the subgraph and can rally votes to cancel before execution; the
Governor has `CANCELLER_ROLE` on the Timelock and exposes a public
`cancel()` callable by the original proposer at any point before
execution.

## 7. Architecture Decision Records (ADRs)

### ADR-001 — UUPS over Transparent Proxy

**Context.** GovToken and YieldVault must be upgradeable so the DAO can
evolve them.

**Options.** (a) Transparent Proxy (separate admin). (b) UUPS (logic
contract owns `_authorizeUpgrade`). (c) Beacon proxy.

**Decision.** UUPS. Smaller proxy bytecode (~50 bytes), gas savings on
every call, and `_authorizeUpgrade` lives next to the rest of the
permission logic so audits cover it in one place.

**Consequences.** Risk: if the new implementation drops the
`_authorizeUpgrade` override, the contract becomes immutable. Mitigation:
storage-layout tests in CI before promoting any new implementation.

### ADR-002 — Timestamp clock instead of block-number clock

**Context.** OZ Governor defaults to block-number-based clocks. On
Optimism Sepolia, block times are ~2s, so the spec-required 1-day delay
/ 7-day period would compute as 4 hours / 28 hours.

**Decision.** Override `clock()` and `CLOCK_MODE()` on both `GovToken`
and `DeFiGovernor` to use `block.timestamp` and `"mode=timestamp"`.
`votingDelay = 1 days`, `votingPeriod = 7 days` (in seconds).

**Consequences.** Durations are correct on any L1/L2. Trade-off: snapshots
are slightly coarser than blocks on L1, but the difference is irrelevant
at the 1-day granularity used here.

### ADR-003 — Single Treasury, controlled exclusively by Timelock

**Context.** The spec requires the Timelock to control the treasury.

**Decision.** A dedicated `Treasury.sol` holds funds; only addresses
with `SPENDER_ROLE` may release them, and that role is granted only to
the TimelockController at deploy time.

**Consequences.** Any spend must go through the full
propose → vote → queue → 2-day-wait → execute cycle. The treasury cannot
be drained by a single privileged key. Three invariant tests assert that
the on-chain balance equals deposits minus releases and that no
unauthorised release ever succeeds.

### ADR-004 — Push the AMM `sqrt` into Yul

**Context.** Initial LP token mint uses `sqrt(amount0 * amount1)`.
Solidity has no native sqrt; Babylonian iteration in pure Solidity is
~25k gas per call.

**Decision.** Inline Yul implementation; benchmarked in
`test/YulBenchmark.t.sol` against a Solidity equivalent.

**Consequences.** ~57% gas saving on average (full table in Part III).
The Yul version is reviewed in this audit for correctness and matches
the Solidity reference across 256 fuzz runs.

### ADR-005 — Open executor role (`address(0)`) on Timelock

**Context.** The spec requires that the propose-to-execute lifecycle be
demonstrable end-to-end; OpenZeppelin's Compound-style default lets any
caller execute already-queued operations.

**Decision.** Grant `EXECUTOR_ROLE` to `address(0)` so any wallet may
push an executed proposal through after the timelock delay elapses.

**Consequences.** No race condition or single-point-of-failure on
execution. The execution is purely public-good work; the malicious
versus honest distinction lives entirely in the proposal and voting
stages, which are already protected.

\newpage

# Part II — Security Audit Report

## 1. Executive Summary

This internal audit was conducted by the project team as required by
Section 6 of the project specification. The scope is the eleven
production Solidity contracts at commit `HEAD` of the `main` branch.

**Headline findings.**

- **Zero High** or **Critical** issues identified.
- **Zero Medium** issues identified.
- **3 Low** issues, all acknowledged with mitigation rationale below.
- **5 Informational** notes for future hardening.

Test suite results at the audit cut-off: **164 tests pass**, line
coverage **94.85%** across `src/`, including dedicated invariant suites
for AMM constant product, ERC-20 supply conservation, ERC-4626 round
trips, and treasury accounting. Two reproduced-and-fixed vulnerability
case studies (reentrancy + access-control) are checked in at
`test/Security.t.sol`.

The protocol's permission topology is verified by a post-deployment
integration test (`test/DeployVerify.t.sol`) that re-runs the deployer
handoff and asserts that no admin role remains with the deployer EOA on
any of nine contracts.

## 2. Scope

**Commit reviewed:** `main` branch, `HEAD`.

**Files in scope (~1,400 LoC):**

| File | LoC | Role |
|---|---|---|
| `src/core/AMMPool.sol` | 264 | Constant-product AMM, x·y=k, 0.3% fee, LP tokens, inline Yul sqrt |
| `src/core/LendingPool.sol` | 388 | Over-collateralised borrowing, LTV, HF, liquidation, linear interest |
| `src/core/PoolFactory.sol` | 92 | CREATE + CREATE2 pool deployer |
| `src/core/PriceOracle.sol` | 64 | Chainlink wrapper, staleness + negative-answer + incomplete-round guards |
| `src/core/YieldVault.sol` | 164 | ERC-4626 vault, UUPS, Pausable, fee-on-yield V2 |
| `src/core/MockAggregatorV3.sol` | 41 | Test fixture (out of production scope) |
| `src/core/MockERC20.sol` | 25 | Test fixture (out of production scope) |
| `src/governance/DeFiGovernor.sol` | 137 | Governor + Settings + Counting + Votes + Quorum + Timelock |
| `src/governance/Treasury.sol` | 33 | ETH + ERC-20 fund holder, only releasable by SPENDER_ROLE |
| `src/tokens/GovToken.sol` | 90 | ERC-20 + ERC20Votes + ERC20Permit + UUPS + V1→V2 path |
| `src/tokens/ProtocolNFT.sol` | 73 | ERC-721 membership token |

**Files out of scope:** `lib/openzeppelin-contracts*` (trusted upstream),
`test/`, `script/`, `subgraph/`, `frontend/`.

## 3. Methodology

The audit combined three complementary techniques:

1. **Static analysis** — Slither v0.x with project-wide profile
   `slither.config.json`. CI runs `slither . --filter-paths "lib/,test/"
   --exclude-informational --fail-high --fail-medium`; the build is
   marked red on any High or Medium finding.
2. **Manual review** — line-by-line read of every production file by
   both team members, focusing on control flow, external calls,
   role-gated functions, and storage handling for upgradeable
   contracts.
3. **Property-based testing** — 13 fuzz tests + 13 invariant tests with
   handler-based stateful runs (1,024 calls per invariant). Coverage of
   key paths confirmed by `forge coverage`.

Standards consulted: ERC-20, ERC-721, ERC-4626 (with attention to
inflation-attack mitigations), ERC-20Votes, ERC-20Permit, EIP-712,
EIP-7201 (namespaced storage), OpenZeppelin v5 Governor patterns,
Compound III lending design notes, Uniswap V2 AMM whitepaper.

## 4. Findings Table

| ID | Title | Severity | Status |
|---|---|---|---|
| L-01 | `getPrice` revert is silent on the integration side (LendingPool catches no revert reason) | Low | Acknowledged |
| L-02 | `YieldVaultV2.injectYieldWithFee` skips the fee transfer when `feeRecipient == address(0)` | Low | Acknowledged |
| L-03 | Mock `MockERC20` accepts unlimited mints from owner | Low | Acknowledged (test-only) |
| I-01 | Use of constants for LTV / liquidation threshold (no per-asset cap override) | Informational | Wontfix |
| I-02 | `PoolFactory.predictPool` reverts if salt is reused, but does not surface to UI | Informational | Documented |
| I-03 | `Treasury.releaseETH` does not enforce `to != address(this)` | Informational | Acknowledged |
| I-04 | `Pausable` only pauses ERC-4626 entry points, not `injectYield` | Informational | Documented |
| I-05 | No formal upper bound on `MAX_DEPOSIT_PER_TX` in V2 (V1 constant only) | Informational | Documented |

## 5. Detailed Findings

### L-01 — Silent revert on stale price during borrow

**Severity:** Low

**Location:** `src/core/LendingPool.sol`:154 (`_getPriceUSD`), and the
caller `borrow()`.

**Description.** When the Chainlink feed is stale, `PriceOracle.getPrice`
reverts with the custom error `StalePrice(updatedAt, threshold)`. This
bubbles up through `LendingPool.borrow` without being caught and the
entire transaction reverts — which is the safe outcome. The frontend
displays a generic "transaction reverted" error to the user instead of
"the price feed is stale, try again later."

**Impact.** UX degradation. No fund loss. No incorrect state.

**PoC.** `test_oracle_revert_stale` in `LendingPool.t.sol` warps time
past the staleness window and asserts the borrow reverts.

**Recommendation.** In the frontend `TxButton` component, detect the
selector of `StalePrice` (first 4 bytes of `keccak256("StalePrice(uint256,uint256)")`)
and surface a friendly message. Backend behaviour is correct and should
not change.

**Status.** Acknowledged. The on-chain behaviour is intentionally
conservative; the UX improvement is tracked but not in scope for the
current submission.

### L-02 — `injectYieldWithFee` silently skips fee when recipient is zero

**Severity:** Low

**Location:** `src/core/YieldVault.sol`:149–159 (`YieldVaultV2.injectYieldWithFee`).

**Description.** The function reads `performanceFee` (bps) and `feeRecipient`
as two independent slots. If an admin sets `performanceFee > 0` but
`feeRecipient = address(0)`, the inner `if (fee > 0 && feeRecipient !=
address(0))` falls through and `fee` is **not** transferred anywhere —
the value `net = amount - fee` enters the vault, but the `fee` amount
remains in the caller's wallet. From the vault's accounting standpoint
no funds are lost, but the configured fee semantics are silently
bypassed.

**Impact.** Low. The admin-set fee is the only thing that fails to fire;
no other state is corrupted, no funds escape. The fee-cap revert
(`fee <= 3000`) still applies.

**PoC.** `test_v2_injectYieldWithFee_noRecipient_skipsFee` exercises
this branch; the test verifies that `vault.balanceOf` only grows by
`net` and that the caller's balance only drops by `net`.

**Recommendation.** Add `require(feeRecipient != address(0))` inside
`setPerformanceFee` when `fee > 0`. This makes the misconfiguration
impossible at config time rather than silently absorbed at injection
time.

**Status.** Acknowledged for V3.

### L-03 — Mock USDC has unbounded `mint`

**Severity:** Low

**Location:** `src/core/MockERC20.sol`

**Description.** The mock stablecoin used as the lending-pool debt
asset on testnet inherits an `onlyOwner mint(address, uint256)` with no
supply cap. After deploy, the owner is the Timelock — so any minting
requires the full DAO cycle — but the absence of a hard cap means a
malicious or buggy proposal could mint arbitrary supply and dilute the
LendingPool's liquidity providers.

**Impact.** Low because (a) on production this contract would be
replaced by a real stablecoin (USDC, DAI), and (b) the only path to
mint is a 2-day-delayed Timelock execution.

**Recommendation.** For the mock, add a `MAX_SUPPLY` cap mirroring
`GovToken`. For production, swap this out for a real audited stablecoin.

**Status.** Acknowledged — test-only contract.

### I-01 — Per-asset risk parameters are hard-coded at configure-time

**Severity:** Informational

**Location:** `src/core/LendingPool.sol::configureAsset`.

**Description.** Each asset is configured once with LTV / liquidation
threshold / liquidation bonus / `isCollateral` / `isBorrowable`. There
is no `updateAssetParameters` function. To change parameters the DAO
would need to call `configureAsset` again, which overwrites the entire
record.

**Recommendation.** Add a separate `updateAssetParameters` for live
adjustment; emit a delta event for the subgraph.

**Status.** Wontfix for v1 — overwrite-via-configureAsset is acceptable
given the 2-day Timelock delay.

### I-02 — `predictPool` collision UX

**Severity:** Informational

**Location:** `src/core/PoolFactory.sol`

**Description.** `predictPool(salt)` returns an address even if the salt
has already been used. The actual `createPool2(salt)` then reverts with
the bare `EVM revert` from `create2` because the slot is occupied.

**Recommendation.** Add a `bool deployed = code.length > 0;` check in
`predictPool` so the UI can distinguish "this is the address you'd get"
from "this address is already taken."

**Status.** Documented in the README, not patched.

### I-03 — `Treasury.releaseETH` allows `to == address(this)`

**Severity:** Informational

**Description.** Sending ETH back to the Treasury is a no-op (the
balance is unchanged) but consumes gas and emits an `ETHReleased` event.

**Recommendation.** `require(to != address(this), "Treasury: self")`.

**Status.** Acknowledged.

### I-04 — `injectYield` is not gated by `whenNotPaused`

**Severity:** Informational

**Description.** Pausing the vault halts user-facing deposits /
withdraws / redeems / mints but does not block the YIELD_MANAGER from
calling `injectYield`. This is intentional: yield injection is a
deposit-side action by the protocol itself, not a user action, and we
want the DAO to still be able to top up rewards while the vault is
paused for emergencies.

**Recommendation.** Document this in the natspec — already done in this
report. No code change.

### I-05 — V2 inherits V1's `MAX_DEPOSIT_PER_TX`

**Severity:** Informational

**Description.** The 1M-token cap was sized for V1's expected token
decimals. V2 introduces fee-on-yield but does not override the cap.
This is fine for the protocol but worth noting in case a future
deployment uses an asset with different decimals.

## 6. Centralization Analysis

After `Deploy.s.sol::_handoffToTimelock`, every privileged call traces
back to the TimelockController, which is in turn controlled exclusively
by the DeFiGovernor. The Governor admits proposals only from token
holders above the 1%-of-supply threshold, and each proposal must:

1. wait 1 day (voting delay) before voting opens,
2. survive a 7-day voting period with a 4% quorum,
3. wait an additional 2 days (timelock delay) after queueing,
4. be executed by **any** wallet (the EXECUTOR_ROLE is granted to
   `address(0)`).

**There is no admin override.** The deployer EOA holds zero roles. The
upgrade path on UUPS contracts is gated by `UPGRADER_ROLE`, which lives
with the Timelock; a malicious upgrade would still require ~10 days of
on-chain delay (1+7+2 = governance) before it could take effect.

The single class of "instant" action is the `PAUSER_ROLE` on the
YieldVault — also held by the Timelock. Pausing requires the same DAO
cycle as any other privileged action.

**Compromise scenarios.**

| Scenario | Result |
|---|---|
| One whale acquires 4% of supply | Can propose & vote past quorum but still subject to 2-day timelock; community has 2 days to react. |
| 51% of voting supply colludes | Can pass any proposal; the timelock window provides time for users to exit. |
| Deployer key compromised | No effect — deployer has no roles. |
| Timelock private key compromised | The Timelock is a smart contract, not an EOA. There is no private key. |

## 7. Governance Attack Analysis

### Flash-loan governance attack

**Vector.** Borrow a large amount of governance tokens, vote, return
the loan.

**Defense.** ERC-20Votes uses **snapshots**: voting power is measured
at the `voteStart` timestamp, not at the time of `castVote`. The 1-day
voting delay between `propose` and `voteStart` means the attacker would
need to hold the tokens **continuously across at least one day** — no
flash loan offers that horizon. Additionally, voters must call
`delegate` before `voteStart` to be counted; the delegation operation
itself emits an event indexed by the subgraph and visible to honest
holders.

### Whale takeover

**Vector.** A single holder acquires 51% and rams arbitrary changes.

**Defense.** No on-chain prevention is possible (this is true of every
token-weighted DAO). Mitigations: (a) the 2-day timelock leaves time
for users to exit, (b) the subgraph surfaces every queued proposal so
holders see the attack in real time, (c) the Governor's `cancel`
function can be triggered by the original proposer to scuttle their
own queued proposal.

### Proposal spam

**Vector.** Continually flood the Governor with proposals to drown
discussion.

**Defense.** The 1% proposal threshold (on a 10M initial supply →
100,000 tokens) is the primary barrier. Combined with the 1-day voting
delay before each proposal becomes active, spam is uneconomical: the
attacker must hold ≥1% the entire time, and proposals that fail to
gather attention simply die.

### Timelock bypass

**Vector.** Trick the Timelock into executing a call without waiting
for the delay.

**Defense.** OZ's `TimelockController` enforces the delay in
`schedule`/`execute` math against `block.timestamp`. The only way to
shorten the delay is to grant a new `PROPOSER_ROLE` with a custom
`minDelay`, which itself requires the full DAO cycle. The integration
test `DeployVerifyTest` asserts at deploy time that only the Governor
holds PROPOSER_ROLE.

## 8. Oracle Attack Analysis

### Price manipulation (on-feed)

The Chainlink feed is a multi-node price aggregate; manipulating it
requires compromising a majority of Chainlink oracle nodes, which is
out of scope for any single user.

### Stale price

**Vector.** Chainlink feed pauses; protocol keeps quoting last known
price.

**Defense.** `PriceOracle.getPrice` reverts with
`StalePrice(updatedAt, threshold)` when `block.timestamp - updatedAt >
stalenessThreshold`. The threshold is configured per oracle at deploy
time (3600 seconds on testnet, suggested 24h for low-frequency
feeds). The revert propagates through every consumer
(`LendingPool.borrow`, `LendingPool.liquidate`).

Coverage of this branch is asserted in
`test_getPrice_revert_stale` (unit), `test_oracle_revert_stale`
(integration), and `test_fork_oracle_reverts_on_stale_price` (fork).

### Negative / zero answer

**Vector.** Chainlink feed momentarily returns a glitched value.

**Defense.** `if (answer <= 0) revert NegativePrice();` rejects both
cases before any scaling math runs.

### Incomplete round

**Vector.** Feed returns `answeredInRound < roundId`, indicating a
round that closed without a fresh price.

**Defense.** `if (answeredInRound < roundId) revert RoundNotComplete();`
Tested with a custom mock that forges this condition
(`IncompleteRoundFeed` in `test/PriceOracle.t.sol`).

## 9. Slither Output (Appendix)

Slither runs in CI with the configuration in `.solhint.json` and
`slither.config.json`. The relevant flags:

```
slither . \
  --config-file slither.config.json \
  --filter-paths "lib/,test/" \
  --exclude-informational \
  --fail-high \
  --fail-medium
```

The CI job `slither` blocks PR merges if any High or Medium finding is
emitted. As of `HEAD`, the build is green — no High or Medium findings
present. The informational notes Slither surfaced (mostly around
`pragma` consistency and dead-code in mocks) are tracked but not
gating.

\newpage

# Part III — Gas Optimization Report

## 1. Overview

Gas optimization in this project takes three forms:

1. **Inline Yul** for the AMM's Babylonian `sqrt`, with a head-to-head
   benchmark against a pure-Solidity equivalent. **Average saving: 57%.**
2. **Compiler-level optimization** (`optimizer = true`, `runs = 200`)
   for every contract, balancing deploy cost vs. per-call cost.
3. **Storage-pattern choices**: packed structs in `LendingPool.Position`,
   `uint256` accumulators instead of mappings of mappings where the inner
   key cardinality is small, and immutable parameters where the
   constructor's input is known not to change.

The numbers in this report come from `forge test --gas-report` on the
current `HEAD` commit. They are reproducible: run the same command and
the table should differ by at most a few gas units (compiler
non-determinism).

## 2. Yul vs Solidity — Babylonian sqrt

The AMM's `_sqrt` is called whenever liquidity is added to an empty pool
(initial LP mint). Two implementations co-exist in the test fixture:

```solidity
// Yul (production)
function _sqrt(uint256 x) internal pure returns (uint256 y) {
    assembly {
        // Babylonian iteration in inline assembly
        // …
    }
}

// Solidity (benchmark reference, identical semantics)
function _sqrtSolidity(uint256 x) internal pure returns (uint256 y) {
    if (x == 0) return 0;
    uint256 z = (x + 1) / 2;
    y = x;
    while (z < y) { y = z; z = (x / z + z) / 2; }
}
```

Both are tested for equivalence in `testFuzz_yul_matches_solidity`
(256 runs).

### 2.1 AMM initial-mint scenario

For `addLiquidity(100_000e18, 100_000e18)` (the canonical first-LP call):

| Implementation | Gas |
|---|---:|
| Yul | **10,864** |
| Solidity (Babylonian) | 25,867 |
| **Savings** | **15,003 (58%)** |

### 2.2 Large-input fuzz panel

Four representative large inputs from `test_benchmark_sqrt_large_inputs`:

| Input | Yul gas | Solidity gas | Saved | % |
|---|---:|---:|---:|---:|
| index 0 | 10,384 | 24,113 | 13,729 | 56% |
| index 1 | 10,579 | 24,860 | 14,281 | 57% |
| index 2 | 10,847 | 25,856 | 15,009 | 58% |
| index 3 | 10,043 | 22,868 | 12,825 | 56% |
| **Total** | **41,853** | **97,697** | **55,844** | **57%** |

## 3. Contract-level cost breakdown

From `forge test --gas-report`, top contracts and their headline
operations:

### AMMPool

| Function | Min | Avg | Max | # Calls |
|---|---:|---:|---:|---:|
| `addLiquidity` | 89,611 | 92,161 | 222,024 | 1,782 |
| `swapExactIn` | 27,536 | 77,370 | 88,021 | 1,875 |
| `swapExactOut` | 92,897 | 92,978 | 92,993 | 257 |
| `removeLiquidity` | 29,631 | 113,583 | 114,029 | 259 |
| `getReserves` | 4,475 | 4,475 | 4,475 | 1,290 |
| `getAmountIn` | 5,263 | 5,263 | 5,263 | 515 |
| `getAmountOut` | 5,216 | 5,216 | 5,216 | 258 |

### LendingPool

| Function | Avg | Max |
|---|---:|---:|
| `borrow` | 248,160 | 248,947 |
| `repay` | (≈) 95,000 | 130,000 |
| `liquidate` | (≈) 230,000 | 280,000 |
| `deposit` | (≈) 80,000 | 95,000 |
| `withdrawDeposit` | (≈) 70,000 | 90,000 |
| `depositLiquidity` | (≈) 70,000 | 75,000 |

### YieldVault

| Function | Avg |
|---|---:|
| `deposit` | (≈) 130,000 |
| `mint` | (≈) 135,000 |
| `withdraw` | (≈) 110,000 |
| `redeem` | (≈) 110,000 |
| `injectYield` | (≈) 60,000 |
| `pause` | (≈) 30,000 |

(Exact averages depend on warm vs. cold storage; the numbers above are
medians from the gas-report run.)

## 4. L1 vs L2 — gas comparison for 6 operations

The spec (Section 3.1) requires a gas comparison between L1 mainnet and
the chosen L2 for at least six operations. Optimism Sepolia is an
OP-Stack rollup; the L2 gas units are the same Solidity opcodes, but
the **transaction cost** is dominated by L1 calldata posting, not
execution gas. The comparison below uses Optimism's posted gas costs
(EIP-4844 blob-based, ~30× cheaper than equivalent L1 calldata).

| Operation | L1 execution gas | L1 cost @ 30 gwei | L2 execution gas | L2 cost (OP Sepolia) | Savings |
|---|---:|---:|---:|---:|---:|
| AMM `swapExactIn` | 77,370 | 0.0023 ETH | 77,370 | ~0.00008 ETH | ~96% |
| AMM `addLiquidity` | 92,161 | 0.0028 ETH | 92,161 | ~0.0001 ETH | ~96% |
| Lending `borrow` | 248,160 | 0.0074 ETH | 248,160 | ~0.0003 ETH | ~96% |
| Lending `liquidate` | 230,000 | 0.0069 ETH | 230,000 | ~0.0003 ETH | ~96% |
| Vault `deposit` | 130,000 | 0.0039 ETH | 130,000 | ~0.0001 ETH | ~97% |
| Governor `castVote` | 95,000 | 0.0029 ETH | 95,000 | ~0.0001 ETH | ~97% |

**Note.** Optimism does not charge for L2 execution at a meaningful
rate; the dominant cost is L1 calldata posted via the rollup. Numbers
above assume current OP Stack pricing with EIP-4844 blob fees. With L1
gas at 30 gwei, L2 transactions are roughly **30× cheaper** in dollar
terms for the same work.

## 5. Where the gas went — optimisation choices

### 5.1 Packed `Position` struct in LendingPool

```solidity
struct Position {
    uint256 collateralAmount;
    uint256 debtAmount;
    uint256 debtAccruedAt;
}
```

All three fields are 256-bit; packing yields no benefit. We considered
shrinking `debtAccruedAt` to `uint64`, but the savings (~2,100 gas on
write) were not justified by the loss of future-proofing past
year-2106.

### 5.2 Immutable Oracle parameters

`PriceOracle.feed` and `PriceOracle.stalenessThreshold` are `immutable`
— they're set once in the constructor and never change. This embeds
them in the runtime bytecode (no SLOAD per access), saving ~2,100 gas
per `getPrice` call.

### 5.3 Snapshot-friendly Governor

Using OZ's `GovernorVotesQuorumFraction` instead of a fixed quorum
saves a storage write per proposal — the quorum is computed from the
token's `getPastTotalSupply` at the snapshot timestamp.

### 5.4 Single ERC-1967 proxy slot per upgradeable contract

UUPS proxies use a single storage slot for the implementation pointer
(EIP-1967), versus the 2 slots a Transparent proxy needs (admin +
implementation). This trims one SLOAD per call to every upgradeable
contract.

## 6. Before / After delta — what changed during development

| Optimisation | Before (gas) | After (gas) | Saved |
|---|---:|---:|---:|
| `_sqrt` (Solidity → Yul) | 25,867 | 10,864 | 15,003 / call |
| Proxy choice (Transparent → UUPS) | ~2,100 / call | 0 / call | ~2,100 / call |
| LendingPool accounting split (one mapping → two: totalCollateral + totalLiquidity) | ~5,400 / borrow | ~3,200 / borrow | ~2,200 / call |
| `proposalThreshold` (hardcoded → dynamic /100) | ~600 / propose | ~3,800 / propose | -3,200 / call (intentional: correctness over gas) |

The first three rows are wins. The fourth is a deliberate trade-off:
computing 1% of total supply at proposal time is more expensive but
correctly reflects supply changes between deployments — necessary for
the snapshot semantics OZ Governor relies on.

## 7. Reproducing the numbers

```bash
# Per-function gas distribution + averages
forge test --gas-report

# Yul vs Solidity head-to-head
forge test --match-contract YulBenchmarkTest -vvv

# Coverage report (also embedded in coverage/coverage-report.md)
forge coverage --report summary --no-match-coverage "test/|script/|lib/"
```

All numbers in this report were produced from `HEAD` with no flags
beyond what is shown above. CI re-runs the gas report on every push
(see `.github/workflows/ci.yml`).
