---
paths:
  - "src/**"
---

# Protocol Core

The on-chain DSC stablecoin protocol: `DSCEngine` (collateral + mint/burn + liquidation), `DecentralizedStableCoin` (the ERC20 the engine mints), and `libraries/OracleLib` (Chainlink staleness wrapper). The engine owns the token; the library is the engine's only path to a price feed.

## Design intent

- DSC is over-collateralized: collateral USD value must exceed minted USD value by the configured threshold. The single protocol invariant is the health factor — every public entry point that moves collateral or DSC closes with a check that the *caller's* health factor is at or above the minimum.
- Liquidators repay debt and receive collateral plus a fixed bonus, funded by the liquidated user. This bonus is the only incentive — there is no automated keeper, so the bonus has to be big enough to attract one.
- Stale Chainlink data freezes the protocol *by design*. Don't bypass `OracleLib.staleCheckLatestRoundData` for a "fresher" or "fallback" price read — a frozen protocol is the intended failure mode.
- `DecentralizedStableCoin` is `Ownable`; the deploy script transfers ownership to the engine. The engine is the only minter. Don't add a second minter or a governance hook — the single-owner constraint is what lets the engine treat `i_dsc.mint` as a trusted call.

## Patterns

- State updates first, external transfers second, health-factor check last. `_redeemCollateral` and `_burnDsc` are private precisely so this ordering is enforced at the public entry point that wraps them.
- Modifier order on new public/external entry points: input checks (`moreThanZero`, `isAllowedToken`), then `nonReentrant`. Mirror this so the cheap checks short-circuit before the reentrancy slot write.
- Decimal handling: Chainlink feeds are scaled up by `ADDITIONAL_FEED_PRECISION` (feeds report 8-dec, math runs in 18-dec). Collateral tokens with fewer than 18 decimals are scaled up via `s_decimals[token]`. Reject tokens with more than 18 decimals at construction — the engine has no scale-down path.
- The constants block (`LIQUIDATION_THRESHOLD`, `LIQUIDATION_BONUS`, `LIQUIDATION_PRECISION`, `MIN_HEALTH_FACTOR`, `PRECISION`, `ADDITIONAL_FEED_PRECISION`) is the protocol's policy surface. Changing a number here is a protocol change, not a refactor — propagate to the tests' mirrored constants.

## Conventions

- Errors are named `<Contract>__<Reason>` (e.g. `DSCEngine__BreaksHealthFactor`). Keep this prefix so reverts are unambiguous in traces.
- External getters mirror private state with a `get` prefix and minimal logic — they exist so off-chain consumers never depend on storage layout.
- Slither suppressions are inline `// slither-disable-next-line <detector>` with a one-line justification on the preceding comment line. Preserve them; if you remove the suppressed code, remove the comment too.

## Gotchas

- `s_collateralTokens` is iterated on every `getTotalCollateralValueInUsd` call (which itself is called on every health-factor evaluation). Adding many collateral tokens is a hidden loop-gas / out-of-gas risk on liquidation paths.
- `_calculateHealthFactor` returns `type(uint256).max` when nothing is minted. Code that compares health factor to a threshold must treat this as "infinitely healthy" rather than an overflow.
- `OracleLib.TIMEOUT` is a single fixed window applied to every feed. If a feed's natural heartbeat exceeds it the protocol freezes on healthy data — tune per-feed if you add one with a slower update cadence.
