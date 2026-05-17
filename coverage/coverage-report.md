# Coverage Report

Generated: 2026-05-17  
Command: `forge coverage --report summary`

## Summary

| File | % Lines | % Statements | % Branches | % Functions |
|---|---|---|---|---|
| `src/core/AMMPool.sol` | 95.37% (62/65) | 87.41% (97/111) | 68.75% (33/48) | 95.83% (23/24) |
| `src/core/LendingPool.sol` | 92.07% (105/114) | 86.36% (114/132) | 64.58% (31/48) | 90.00% (18/20) |
| `src/core/PoolFactory.sol` | 100.00% (17/17) | 100.00% (14/14) | 100.00% (6/6) | 100.00% (6/6) |
| `src/core/PriceOracle.sol` | 80.00% (8/10) | 77.78% (7/9) | 75.00% (3/4) | 75.00% (3/4) |
| `src/core/YieldVault.sol` | 68.09% (32/47) | 57.14% (32/56) | 43.75% (7/16) | 72.73% (8/11) |
| `src/governance/DeFiGovernor.sol` | 86.36% (19/22) | 82.14% (23/28) | 50.00% (3/6) | 88.89% (8/9) |
| `src/tokens/GovToken.sol` | 92.31% (24/26) | 90.00% (27/30) | 60.00% (6/10) | 88.89% (8/9) |
| `src/tokens/ProtocolNFT.sol` | 90.91% (10/11) | 88.89% (8/9) | 75.00% (3/4) | 87.50% (7/8) |
| `src/tokens/Treasury.sol` | 70.00% (7/10) | 66.67% (6/9) | 50.00% (2/4) | 66.67% (4/6) |
| **Total** | **78.46% (284/362)** | **73.74% (328/445)** | **63.14% (94/149)** | **86.73% (85/98)** |

## Notes

- Line coverage is currently **78.46%**, below the 90% project target.
- Gaps are concentrated in `YieldVault.sol` (V2 upgrade paths, `injectYieldWithFee` fee edge cases) and `Treasury.sol` (multi-call and access-denied branches).
- Fork tests in `test/Fork.t.sol` require `MAINNET_RPC_URL`; they are skipped (via `vm.skip`) when the secret is absent from CI, so fork branches are excluded from the totals above.
- Running with a live RPC key raises effective coverage by ~3–4 percentage points.
