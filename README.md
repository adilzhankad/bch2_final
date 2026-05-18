# DeFi Super-App — Blockchain Capstone (BCH2 Final)

**Option A**: AMM + Lending Protocol + ERC-4626 Yield Vault + DAO Governance + Chainlink + The Graph + L2 deployment

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│                      DAO Governance Layer                    │
│   DeFiGovernor (OZ Governor)  ←→  TimelockController (2d)  │
│              ↑ votes via GovToken (ERC20Votes)              │
└────────────────────────────┬────────────────────────────────┘
                             │ controls
┌────────────────────────────▼────────────────────────────────┐
│                      Core Protocol Layer                     │
│                                                              │
│  PoolFactory ──(CREATE/CREATE2)──→ AMMPool (x·y=k, 0.3%)   │
│                                                              │
│  LendingPool ←─ PriceOracle ←─ Chainlink AggregatorV3      │
│    (LTV, health factor, liquidation, linear interest)        │
│                                                              │
│  YieldVault (ERC-4626, UUPS, Pausable)                      │
└─────────────────────────────────────────────────────────────┘
```

### Contracts

| Contract | Path | Description |
|---|---|---|
| `GovTokenV1/V2` | `src/tokens/GovToken.sol` | ERC20Votes + ERC20Permit, UUPS proxy |
| `ProtocolNFT` | `src/tokens/ProtocolNFT.sol` | ERC-721 membership NFT |
| `AMMPool` | `src/core/AMMPool.sol` | Constant-product AMM, inline Yul sqrt |
| `PoolFactory` | `src/core/PoolFactory.sol` | CREATE + CREATE2 factory |
| `LendingPool` | `src/core/LendingPool.sol` | Collateral, LTV, liquidation, interest |
| `YieldVaultV1/V2` | `src/core/YieldVault.sol` | ERC-4626, UUPS upgradeable, Pausable |
| `PriceOracle` | `src/core/PriceOracle.sol` | Chainlink wrapper + staleness check |
| `MockAggregatorV3` | `src/core/MockAggregatorV3.sol` | Test mock for Chainlink feed |
| `DeFiGovernor` | `src/governance/DeFiGovernor.sol` | Full Governor + Timelock stack |

---

## Key Design Decisions

### UUPS Upgrade Pattern (V1 → V2)
Both `GovTokenV1` and `YieldVaultV1` follow UUPS:
- Implementation has `_disableInitializers()` in constructor
- Proxy calls `initialize()` on first deployment
- `upgradeToAndCall()` restricted to `UPGRADER_ROLE`
- V2 adds new features (version getter, performance fee) without breaking V1 state

### Factory: CREATE vs CREATE2
- `createPool()` — standard `new AMMPool(...)`, non-deterministic address
- `createPool2(salt)` — inline assembly `create2`, deterministic address
- `predictPool(salt)` — pre-compute the CREATE2 address off-chain

### Inline Yul Assembly (AMMPool.sol)
Babylonian square root used for initial LP token minting:
```solidity
function _sqrt(uint256 x) internal pure returns (uint256 y) {
    assembly {
        // ~40% cheaper gas vs pure-Solidity iterative approach
        ...
    }
}
```

### Chainlink Staleness Check
`PriceOracle.getPrice()` reverts with `StalePrice` if `block.timestamp - updatedAt > stalenessThreshold`.

### Governance Parameters
| Parameter | Value |
|---|---|
| Voting delay | 1 day (~7 200 blocks) |
| Voting period | 1 week (~50 400 blocks) |
| Quorum | 4% of total supply |
| Proposal threshold | 1% of total supply |
| Timelock delay | 2 days |

### Security Patterns
- **CEI** (Checks-Effects-Interactions) throughout all state-changing functions
- **ReentrancyGuard** on AMM and LendingPool
- **SafeERC20** for all token transfers
- **AccessControl** for admin functions
- No `tx.origin` auth, no `block.timestamp` randomness
- No `transfer`/`send` — uses `call{value:}` via SafeERC20

---

## Test Suite

**132 tests passing** (4 fork tests skipped without a mainnet RPC key).

```
test/
├── AMMPool.t.sol        — 18 (unit + 4 fuzz)
├── GovToken.t.sol       — 16 (unit + 1 fuzz + upgrade path)
├── Governance.t.sol     — 13 (full lifecycle + 2 fuzz + treasury control)
├── LendingPool.t.sol    — 35 (unit + 2 fuzz)
├── YieldVault.t.sol     — 12 (unit + 2 fuzz)
├── ProtocolNFT.t.sol    — 15 (unit + 1 fuzz)
├── Security.t.sol       —  7 (reentrancy + access-control case studies)
├── Invariants.t.sol     — 10 (k, LP supply, reserves, totalSupply, maxSupply,
│                              ERC-4626 round-trips, vault totalAssets)
├── YulBenchmark.t.sol   —  6 (Yul sqrt vs Solidity, fuzz + gas)
├── DeployVerify.t.sol   —  1 (post-deployment spec verification)
└── Fork.t.sol           —  4 (Chainlink ETH/USD, USDC ERC-20 on mainnet)
```

Breakdown vs. spec minimums:
- Unit: 100+ (≥50 required)
- Fuzz: 13 (≥10 required)
- Invariant: 10 (≥5 required)
- Fork: 4 (≥3 required)

---

## Quick Start

```bash
# Install Foundry
curl -L https://foundry.paradigm.xyz | bash && foundryup

# Clone and install dependencies (already in lib/)
git clone <repo> && cd bch2_final

# Build
forge build

# Test
forge test -vv

# Coverage (report saved to coverage/coverage-report.md)
forge coverage --report summary | tee coverage/coverage-report.md

# Deploy to Optimism Sepolia
cp .env.example .env   # fill PRIVATE_KEY, OPTIMISM_SEPOLIA_RPC_URL
forge script script/Deploy.s.sol --rpc-url optimism_sepolia --broadcast --verify

# Verify deployment (checks Timelock holds all admin roles, deployer has none)
forge test --match-contract DeployVerifyTest -vv
```

---

## Deployed Contracts (Optimism Sepolia, chain id 11155420)

All contracts verified on [sepolia-optimism.etherscan.io](https://sepolia-optimism.etherscan.io).

| Contract | Address |
|---|---|
| PoolFactory   | [`0x854B46B5DD326308bE89CA0f87aF7aece562E690`](https://sepolia-optimism.etherscan.io/address/0x854B46B5DD326308bE89CA0f87aF7aece562E690) |
| LendingPool   | [`0x8a7968Af678dc57F900Fee73944Ce175019f7141`](https://sepolia-optimism.etherscan.io/address/0x8a7968Af678dc57F900Fee73944Ce175019f7141) |
| YieldVault    | [`0xc3918E6Dad6E59C5d33A31948CCfC13563bf0428`](https://sepolia-optimism.etherscan.io/address/0xc3918E6Dad6E59C5d33A31948CCfC13563bf0428) |
| DeFiGovernor  | [`0xcc26c270bCB0989a9Eb1d4Fe4D26caE3C2073eca`](https://sepolia-optimism.etherscan.io/address/0xcc26c270bCB0989a9Eb1d4Fe4D26caE3C2073eca) |
| ProtocolNFT   | [`0x6E84187542a1310f6dE482A4f8569F00eF6AbC62`](https://sepolia-optimism.etherscan.io/address/0x6E84187542a1310f6dE482A4f8569F00eF6AbC62) |

### Post-Deployment Verification

After deployment, the script [`script/Verify.s.sol`](script/Verify.s.sol) checks
that the live state matches the spec:

- Timelock delay is exactly 2 days
- Governor parameters: 1-day delay, 7-day period, 4% quorum, 1% proposal threshold
- Every `AccessControl` contract has the TimelockController as `DEFAULT_ADMIN_ROLE`
- Ownable contracts (PoolFactory, mUSDC) are owned by the TimelockController
- Deployer EOA holds **zero** admin roles anywhere — no backdoor

The expected output and the full check list are in
[`script/verification/output.md`](script/verification/output.md). The
integration test `DeployVerifyTest` replays the same checks in CI on every push.

---

## Frontend Setup

```bash
cd frontend

# 1. Copy env template and fill in values
cp .env.local.example .env.local

# 2. Install dependencies
npm install

# 3. Start dev server
npm run dev
```

### Frontend Environment Variables

Edit `frontend/.env.local` after copying from `.env.local.example`:

| Variable | Description |
|---|---|
| `NEXT_PUBLIC_WALLETCONNECT_PROJECT_ID` | Free key from [cloud.walletconnect.com](https://cloud.walletconnect.com) |
| `NEXT_PUBLIC_GOV_TOKEN` | Deployed GovToken proxy address (Optimism Sepolia) |
| `NEXT_PUBLIC_AMM_POOL` | Deployed AMMPool address |
| `NEXT_PUBLIC_YIELD_VAULT` | Deployed YieldVault proxy address |
| `NEXT_PUBLIC_LENDING_POOL` | Deployed LendingPool address |
| `NEXT_PUBLIC_GOVERNOR` | Deployed DeFiGovernor address |
| `NEXT_PUBLIC_TIMELOCK` | Deployed TimelockController address |
| `NEXT_PUBLIC_TREASURY` | Deployed Treasury address |
| `NEXT_PUBLIC_SUBGRAPH_URL` | The Graph studio endpoint (after subgraph deployment) |

---

## Environment Variables (Contracts / CI)

```
PRIVATE_KEY=0x...
OPTIMISM_SEPOLIA_RPC_URL=https://sepolia.optimism.io
MAINNET_RPC_URL=https://eth-mainnet.alchemyapi.io/v2/<key>
ETHERSCAN_API_KEY=...
```

---

## Team

| Name | GitHub | Area of Ownership |
|---|---|---|
| Adilzhan Kadyrov | [@adilzhankadyrov](https://github.com/adilzhankadyrov) | Lending pool, vault, deployment, frontend, CI |
| Dastan Bekesh    | [@BekeshDastan](https://github.com/BekeshDastan)     | AMM, governance, tokens, subgraph |
