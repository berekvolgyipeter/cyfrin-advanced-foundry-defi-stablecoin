---
paths:
  - "test/invariant/**"
---

# Invariant Tests

Layered on `tests.md`. Two invariant runners over the same `BaseInvariant`: a strict `FailOnRevertInvariants` (handler calls must succeed under bounded inputs) and a lenient `ContinueOnRevertInvariants` (broader fuzz, reverts ignored). Each registers a single handler contract via `targetContract`.

## Design intent

- The two invariants — total collateral USD value ≥ DSC total supply, and the sum of per-user `dscMinted` equals `totalSupply` — are the protocol's solvency contract. Don't relax them to "fix" a flaky run; the handler is what should adapt.
- `FailOnRevertHandler` pre-bounds every input so each call is reachable from current state (e.g. redeem only up to the amount that keeps health factor ≥ 1). It catches "should-be-valid call unexpectedly reverts" bugs.
- `ContinueOnRevertHandler` deliberately allows reverts and explores wider state (calling without collateral, burning without balance, …). It catches state corruption that survives reverts.
- Handlers track `usersWithCollateral` in an `EnumerableSet` so invariants iterate over the actual fuzzed population. Don't hardcode addresses or use `vm.addr` lists — the set is the source of truth.

## Patterns

- The `depositedCollateral(senderSeed)` modifier resolves `sender` from the user set; `depositedCollateralOrNot(senderSeed)` rolls a fresh address one time in `(numUsers + 1)`. Use these to pick a caller — `msg.sender` inside a fuzz call is the forge runner, not a domain user.
- New handler entry points: bound inputs with `boundSilent` (which suppresses forge's bound-event noise that drowns invariant output), early-`return` on no-op cases, and increment a `*_called` counter so `logSummary` shows whether the call ever landed.

## Gotchas

- The `liquidate` handler is reachable only when a target's health factor has dropped — and there is no price-update path active in either handler, so `liquidate_called` stays at 0 in current runs. The commented-out `updateCollateralPrice` is the intended fix; re-enabling it requires reasoning about the cascading-liquidation invariants first.
- `fail_on_revert = false` in `foundry.toml` is global. Strict suites opt back in with the `forge-config: default.invariant.fail-on-revert = true` comment on the contract. Don't flip the global to chase a single strict run.
- Invariant state persists across calls within a run but resets between runs. Handlers that need seed users must seed inside a call (e.g. `depositCollateral`), not in `setUp` — the runner restarts state, but the targetContract instance is preserved per run.
