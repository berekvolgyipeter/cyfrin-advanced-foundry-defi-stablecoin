---
paths:
  - "test/**"
---

# Tests & Mocks

Unit tests, invariant tests, and mock contracts. Tests deploy through `DeployDSC` (the same path production uses), not by constructing contracts directly — this keeps the test surface honest about the ownership transfer and chain-keyed config selection.

## Design intent

- `DSCEngineTest` is `abstract`; concrete suites extend it to share setup. Add a new unit suite by extending it, not by copying the helpers.
- The `MockDSC*` family (`MockDSCFailedMint`, `MockDSCFailedTransfer`, `MockDSCFailedTransferFrom`, `MockDSCCrashPriceDuringBurn`) exists so the engine's `if (!success) revert ...TransferFailed()` branches and oracle-collapse scenarios are reachable from tests. A new "should never happen" guard in the engine usually needs a matching mock here.
- `ERC20Mock` covers the happy path; `ERC20DecimalsMock` exists specifically to exercise the engine's `< 18` decimal scaling. Use the decimals mock whenever a test cares about WBTC-shaped collateral.
- Test-side constants (`LIQUIDATION_THRESHOLD`, `ADDITIONAL_FEED_PRECISION`, `MIN_HEALTH_FACTOR`, …) mirror the engine's. The duplication is intentional — divergence is a test bug, not a refactor target.

## Conventions

- Path layout drives the Makefile: `test/unit/*.t.sol` for unit, `test/invariant/*.t.sol` for invariants, `test/fuzz/*.t.sol` if/when added. Keep the directory partition so `--match-path` targets stay clean.
- Mocks live under `test/mocks/` and don't import the production token from `src/`. The `MockDSC*` family shares its own base inside that file.

## Gotchas

- `setUp` mints collateral to `user` using whichever token came back from `HelperConfig` — that's a mock with a public `mint` on anvil and the real WETH on sepolia. Running unit tests against a sepolia fork will revert because real WETH has no `mint`. The fork targets in the Makefile are deliberate; don't treat a fork failure as a test bug.
- The `setUp*` helpers (e.g. `setUpDscMintFailed`, `setUpCollateralTransferFailed`) redeploy the engine with a custom mock and re-transfer ownership. Calling them is not idempotent — they replace `dsce` and `dsc` on the test contract. Pick one per test.
