---
paths:
  - "script/**"
---

# Deploy & Interaction Scripts

Forge scripts: `DeployDSC` (single deploy entry), `HelperConfig` (chain-keyed network config), `Interactions` (one contract per write op). These are the only supported way to deploy or hit the protocol from outside tests.

## Design intent

- `HelperConfig` selects a `NetworkConfig` by `block.chainid`. Adding a chain means adding a branch in the constructor and a `getXyzConfig()` factory — not a runtime flag or env var.
- Anvil deploys fresh mocks every run (`MockV3Aggregator`, `ERC20DecimalsMock`). Sepolia returns hard-coded addresses for real Chainlink feeds and canonical WETH/WBTC. `HelperConfig` only opens a broadcast on the anvil branch — never on a real chain.
- `DeployDSC.run` transfers DSC ownership to the engine inside the same broadcast. Splitting this across transactions opens a window where the deployer can still mint — keep it atomic.
- Interaction scripts read the deployed engine + DSC via `DevOpsTools.get_most_recent_deployment(name, chainId)`. They follow the latest broadcast on disk rather than taking addresses as inputs, so re-running `deploy` and then any interaction "just works".

## Patterns

- Each write operation is its own contract inheriting `Interaction` + `Script`. The abstract `Interaction` base holds shared constants (deposit / redeem / mint / burn amounts) so scripts stay single-purpose and the Makefile targets them by contract name.
- Wrap any call that required an ERC20 approval in `try { dsce.xxx(); } catch { token.approve(address(dsce), 0); }`. A revert otherwise leaves a dangling allowance on the engine.
- The anvil branch of `Interaction.getConfig()` rewrites the config's token and feed addresses from the live engine. Each anvil run deploys fresh mocks unrelated to anything `HelperConfig` knows statically — without this rewrite, scripts would point at addresses from a previous broadcast.

## Conventions

- Interaction contract names match the engine function they call (`DepositCollateral`, `MintDsc`, `Liquidate`, …). The Makefile targets reuse those names.
- Tunable parameters live as `constant`s on the `Interaction` base, capitalized with units in the name (`AMOUNT_DSC_MINT`, `AMOUNT_COLLATERAL_DEPOSIT`). Adjust per-run by editing the constant — don't grow constructor signatures.

## Gotchas

- `USER_TO_LIQUIDATE = address(0)` in `Liquidate` is a placeholder — the script reverts until set to a real undercollateralized user. Don't "fix" the placeholder by deleting the script.
- `DevOpsTools.get_most_recent_deployment` reads `./broadcast`. Adding a chain requires confirming `foundry.toml`'s `fs_permissions` still grants read on `./broadcast` and that the new chain's broadcasts land there.
- `vm.envAddress("ADDRESS_DEV")` in `getSepoliaEthConfig` makes the sepolia config side-effectful at construction. Calling `new HelperConfig()` on a sepolia chain id without that env var loaded will revert before any script logic runs.
