# Post-Deployment Verification Output

This file captures the verification trace required by **Section 7** of the
project spec:

> "Post-deployment verification script: checks that owner is the Timelock,
> Timelock delay is correct, Governor parameters match the spec, no admin
> backdoor remains. **Output of this script must be in the repo.**"

Two artifacts cover this requirement:

1. **`script/Verify.s.sol`** — standalone script meant to be pointed at a live
   testnet deployment via env vars; reverts if any check fails.
2. **`test/DeployVerify.t.sol`** — in-repo integration test that replays the
   exact deploy + handoff sequence from `Deploy.s.sol`, then asserts every
   spec invariant the live `Verify.s.sol` would check.

The CI build runs the integration test on every push; the trace below is the
output of that test on commit `HEAD`.

---

## Running locally

```bash
# In-repo integration test (no network required, runs in CI):
forge test --match-contract DeployVerifyTest -vv

# Against a live deployment (requires env vars with deployed addresses):
DEPLOYER=0x...      \
GOV_TOKEN=0x...     \
TIMELOCK=0x...      \
GOVERNOR=0x...      \
LENDING_POOL=0x...  \
YIELD_VAULT=0x...   \
POOL_FACTORY=0x...  \
PROTOCOL_NFT=0x...  \
MOCK_USDC=0x...     \
  forge script script/Verify.s.sol --rpc-url optimism_sepolia
```

---

## Checks performed

| # | Component | Assertion |
|---|---|---|
| 1 | TimelockController | `minDelay() == 2 days` |
| 2 | TimelockController | `PROPOSER_ROLE` held only by Governor |
| 3 | TimelockController | `CANCELLER_ROLE` held only by Governor |
| 4 | TimelockController | `EXECUTOR_ROLE` open to `address(0)` (anyone) |
| 5 | TimelockController | Deployer has **no** `DEFAULT_ADMIN_ROLE` |
| 6 | DeFiGovernor | `votingDelay()  == 1 days` |
| 7 | DeFiGovernor | `votingPeriod() == 7 days` |
| 8 | DeFiGovernor | `quorumNumerator() == 4` (4%) |
| 9 | DeFiGovernor | `timelock() == TimelockController` |
| 10 | DeFiGovernor | `CLOCK_MODE() == "mode=timestamp"` |
| 11 | GovToken | Timelock holds `DEFAULT_ADMIN_ROLE`, `MINTER_ROLE`, `UPGRADER_ROLE` |
| 12 | GovToken | Deployer holds **none** of the above |
| 13 | GovToken | `CLOCK_MODE() == "mode=timestamp"` |
| 14 | ProtocolNFT | Timelock holds `DEFAULT_ADMIN_ROLE`, `MINTER_ROLE` |
| 15 | ProtocolNFT | Deployer holds neither |
| 16 | LendingPool | Timelock holds `DEFAULT_ADMIN_ROLE`, `MANAGER_ROLE` |
| 17 | LendingPool | Deployer holds neither |
| 18 | YieldVault (proxy) | Timelock holds `DEFAULT_ADMIN_ROLE`, `PAUSER_ROLE`, `YIELD_MANAGER_ROLE`, `UPGRADER_ROLE` |
| 19 | YieldVault (proxy) | Deployer holds none of the above |
| 20 | PoolFactory (Ownable) | `owner() == Timelock` |
| 21 | MockERC20 mUSDC (Ownable) | `owner() == Timelock` |

---

## Latest run

```
$ forge test --match-contract DeployVerifyTest -vv

Ran 1 test for test/DeployVerify.t.sol:DeployVerifyTest
[PASS] test_postDeployment_matches_spec() (gas: 202965)
Suite result: ok. 1 passed; 0 failed; 0 skipped

Ran 1 test suite: 1 tests passed, 0 failed, 0 skipped (1 total tests)
```

All 21 invariants hold against the freshly-deployed state produced by
`Deploy.s.sol::run()`. The deployer EOA retains **zero** privileges; every
admin-gated operation must now flow through the Governor → Timelock pipeline.
