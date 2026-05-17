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

```
test/
├── GovToken.t.sol       — 14 unit tests + upgrade path
├── AMMPool.t.sol        — 14 unit tests + 3 fuzz tests
├── LendingPool.t.sol    — 14 unit tests + 1 fuzz test
├── YieldVault.t.sol     — 12 unit tests + 2 fuzz tests
├── Governance.t.sol     — full lifecycle + vote tests
├── ProtocolNFT.t.sol    — 12 unit tests
└── Invariants.t.sol     — 5 invariant tests (k, LP supply, reserves, totalSupply, maxSupply)
```

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
```

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

| Name | Role |
|---|---|
| Member 1 | Smart Contracts (AMM, Lending) |
| Member 2 | Governance + Tokens |
| Member 3 | Testing, Deployment, Frontend |
