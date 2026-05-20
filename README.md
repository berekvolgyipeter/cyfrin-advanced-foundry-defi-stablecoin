# Cyfrin Advanced Foundry DeFi Stablecoin (DSC)

An exogenously-collateralized, USD-pegged, algorithmically-stabilized ERC20. 1 DSC tracks 1 USD, backed by [WETH](https://coinmarketcap.com/academy/article/what-is-wrapped-ethereum-weth) and [WBTC](https://www.wbtc.network) at a 200% collateral ratio with a 10% liquidation bonus. No governance, no fees, no protocol-owned treasury — closer in spirit to single-purpose MakerDAO without DAI's surface area.

Built as the capstone of the [Cyfrin Foundry Solidity Course](https://github.com/Cyfrin/foundry-full-course-cu?tab=readme-ov-file#advanced-foundry-section-3-foundry-defi--stablecoin-the-pinnacle-project-get-here). The [original codebase](https://github.com/Cyfrin/foundry-defi-stablecoin-cu) has been audited by [CodeHawks](https://github.com/Cyfrin/foundry-defi-stablecoin-cu/blob/main/audits/codehawks-08-05-2023.md).

## Protocol

| Property | Choice |
|---|---|
| Peg | USD (1 DSC = $1) |
| Collateral | Exogenous (crypto) — [WETH](https://coinmarketcap.com/academy/article/what-is-wrapped-ethereum-weth) (18 dec), [WBTC](https://www.wbtc.network) (8 dec) |
| Stability mechanism | Minting / burning, algorithmically decentralized — users may only mint with enough collateral |
| Price feeds | [Chainlink](https://docs.chain.link/data-feeds/price-feeds/addresses?network=ethereum&page=1), staleness-checked, with on-chain ETH/BTC ↔ USD conversion helpers |
| Relative stability | Anchored / pegged to the US Dollar |
| Collateral ratio | 200% |
| Liquidation bonus | 10% |

Users deposit collateral and mint DSC against it. If a position's collateral value falls below 200% of its debt, other users may liquidate it by burning DSC on the user's behalf and seizing the same USD value in collateral plus an extra 10% as a bonus — this bonus is the only incentive keeping the currency collateralized, since there is no automated keeper. Self-liquidation is permitted, and a user who liquidates herself does not lose the 10% bonus to a third party.

## Architecture

Three on-chain contracts in a single ownership chain:

- **`DSCEngine`** — entry point for deposit, mint, burn, redeem, liquidate. Custodies collateral, tracks per-user debt, computes the health factor that gates every state-changing call. Exposes `getUsdValue` and `getTokenAmountFromUsd` as the ETH/BTC ↔ USD conversion surface.
- **`DecentralizedStableCoin`** — the ERC20 that `DSCEngine` mints. Ownership is transferred to the engine atomically during deployment, so the engine is the sole minter for the lifetime of the protocol.
- **`OracleLib`** — `using`-attached Chainlink wrapper. Reverts on stale or backwards round data, intentionally freezing the protocol rather than transacting on degraded prices.

## Design notes

- **State-before-transfer ordering.** Every public entry point updates storage, then performs the ERC20 call, then closes with a health-factor check on the caller. The private helpers (`_redeemCollateral`, `_burnDsc`) exist specifically to enforce this ordering at the public boundary.
- **Multi-decimal collateral on one math path.** WBTC (8 dec) and WETH (18 dec) share the engine's valuation logic via per-token decimal scaling applied at deposit accounting and at oracle normalization. Tokens with more than 18 decimals are rejected at construction.
- **Oracle freeze-on-stale.** A single library wraps every Chainlink read. A stale, zero, or out-of-order round halts every priced operation — the protocol prefers freezing to serving wrong prices.
- **Failure-path mocks.** A `MockDSC*` family deliberately returns `false` from `mint` / `transfer` / `transferFrom`, and one variant crashes the oracle mid-burn. These reach the engine's defensive `if (!success) revert` and oracle-collapse branches that would otherwise be untestable.
- **Two-flavor invariant fuzzing.** A strict `FailOnRevertHandler` (every bounded call must succeed) and a lenient `ContinueOnRevertHandler` (broader state exploration with reverts tolerated) drive the same two solvency invariants:
  1. Total collateral USD value ≥ DSC total supply.
  2. Σ per-user `dscMinted` equals `totalSupply`.
- **Slither in CI.** Configured to fail the build on `high` findings, with inline `// slither-disable-next-line` suppressions justified one comment above the disabled line.
- **Chain-keyed deploy + auto-discovering scripts.** `HelperConfig` switches between Anvil mocks and Sepolia's live Chainlink feeds by `block.chainid`. Per-action interaction scripts resolve the latest deployed addresses via `DevOpsTools`, so re-deploying and then calling any action "just works" without passing addresses around.

## Testing

`forge test` runs three tiers under `test/`:

- `unit/` — happy paths and revert-expecting paths, including the failure-path mock suite.
- `invariant/` — paired strict + lenient runners against a stateful handler that tracks fuzzed users in an `EnumerableSet`.
- Sepolia and mainnet fork variants of the unit suite via dedicated Makefile targets.

Line coverage on `src/` is 100%, measured via `make coverage` (`forge coverage` scoped to production sources, invariant runs excluded).

CI runs `forge fmt --check`, `forge build --sizes`, the unit suite, the invariant suite, and Slither on every pull request (and on pushes to `main`/`release`/`develop`).

## Deployment on Sepolia

### Contracts

* [DecentralizedStableCoin](https://sepolia.etherscan.io/address/0x6953688C48B0d111303b348855A3Ce8c4E16ae76)
* [DSCEngine](https://sepolia.etherscan.io/address/0xad2C82d9418061C2D5c38490451Ed69154c24AC6)

### Interactions

* [Deposit collateral and mint DSC](https://sepolia.etherscan.io/tx/0x07c482c5d235c88ec2747b4fa18c533f9f212e8867a1a3522920e831c21af197)
* [Redeem collateral for DSC](https://sepolia.etherscan.io/tx/0x12435fd5f05ce29dbffd931a65e97a95bcbb493beedfe5e1965f1ecb8d8666b7)
* [Deposit collateral](https://sepolia.etherscan.io/tx/0xa6af2ed2f609e96aabe63cd2654340866e09f5defc06a012f4ab662ad7774bb5)
* [Redeem collateral](https://sepolia.etherscan.io/tx/0x3c30eb1741c74a295b5829ee70b1daa220a8f9ae1e298e680543028cffbf3526)
* [Mint DSC](https://sepolia.etherscan.io/tx/0x7ecdca5616b230d0fbb6986bbbf52a8467dac4cb7725464e006d2347b13a921f)
* [Burn DSC](https://sepolia.etherscan.io/tx/0x168500ffce3d3c444e7adc8fd7d36a9aa9a9f544fede5cb1c6620cb0bd852e76)

## Quickstart

```bash
make install         # forge soldeer install
make build
make test            # unit + invariant
make slither
make deploy-sepolia
```

See the [Makefile](Makefile) for the full target list (per-action interaction scripts, coverage, fork tests).
