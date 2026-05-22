# Coverage Report

Generated: 2026-05-18
Command: `forge coverage --report summary --no-match-coverage "test/|script/|lib/"`

## Summary

Line coverage across `src/` is **94.85%**, exceeding the spec minimum of 90%.

| File | % Lines | % Statements | % Branches | % Functions |
|---|---|---|---|---|
| `src/core/AMMPool.sol`            |  95.37% (103/108) |  87.41% (125/143) |  50.00% (16/32) | 100.00% (13/13) |
| `src/core/LendingPool.sol`        |  92.07% (151/164) |  86.36% (190/220) |  48.78% (20/41) |  94.12% (16/17) |
| `src/core/MockAggregatorV3.sol`   |  84.62% (11/13)   |  88.89% (8/9)     | 100.00% (0/0)   |  75.00% (3/4)   |
| `src/core/MockERC20.sol`          |  66.67% (4/6)     |  66.67% (2/3)     | 100.00% (0/0)   |  66.67% (2/3)   |
| `src/core/PoolFactory.sol`        | 100.00% (28/28)   |  91.43% (32/35)   |  40.00% (2/5)   | 100.00% (6/6)   |
| `src/core/PriceOracle.sol`        | 100.00% (20/20)   | 100.00% (22/22)   | 100.00% (10/10) | 100.00% (3/3)   |
| `src/core/YieldVault.sol`         | 100.00% (47/47)   | 100.00% (42/42)   | 100.00% (5/5)   | 100.00% (15/15) |
| `src/governance/DeFiGovernor.sol` | 100.00% (22/22)   |  95.83% (23/24)   |   0.00% (0/1)   | 100.00% (10/10) |
| `src/governance/Treasury.sol`     | 100.00% (10/10)   | 100.00% (8/8)     |  50.00% (1/2)   | 100.00% (3/3)   |
| `src/tokens/GovToken.sol`         | 100.00% (26/26)   | 100.00% (17/17)   | 100.00% (2/2)   | 100.00% (10/10) |
| `src/tokens/ProtocolNFT.sol`      |  90.91% (20/22)   |  94.12% (16/17)   |  50.00% (1/2)   |  87.50% (7/8)   |
| **Total**                         | **94.85% (442/466)** | **89.81% (485/540)** | **57.00% (57/100)** | **95.65% (88/92)** |

## Notes

- Every protocol contract (`AMMPool`, `LendingPool`, `PoolFactory`, `PriceOracle`,
  `YieldVault`, `DeFiGovernor`, `Treasury`, `GovToken`, `ProtocolNFT`) clears
  the 90% line-coverage bar.
- `MockAggregatorV3` and `MockERC20` are test utilities — only the call paths
  exercised by tests are covered; their unused setters and getters drag the
  overall number down slightly but do not affect protocol coverage.
- The single uncovered branch in `DeFiGovernor` is the `clock() == 0` guard
  inside `proposalThreshold()`, which only triggers in the zero-timestamp
  edge case (unreachable on any live chain).
- Fork tests in `test/Fork.t.sol` require `MAINNET_RPC_URL`; they are skipped
  (via `vm.skip(true)`) when the secret is absent from CI, so the
  Chainlink-mainnet branches are not counted above.

## Reproduce

```bash
forge coverage --report summary --no-match-coverage "test/|script/|lib/"
```
