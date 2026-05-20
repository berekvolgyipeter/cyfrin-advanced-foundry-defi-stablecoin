## Rule Files — Progressive Disclosure

Rules in `.claude/rules/` contain curated architectural knowledge: design intent, patterns, constraints, and conventions.

**Before answering questions, researching, or modifying code in any area below:** read the relevant rule file(s) FIRST. They explain the "why" and "how" without needing to scan source files. Only dive into source code for details the rules don't cover.

| Rule file | Triggers on | Covers |
|---|---|---|
| `protocol.md` | `src/**` | DSC engine, token, and oracle library: health-factor invariant, state-before-transfer ordering, oracle freeze-on-stale, ownership chain, decimal scaling |
| `scripts.md` | `script/**` | Deploy + chain-keyed `HelperConfig` + per-action `Interactions`: `DevOpsTools` lookup, approval-revoke try/catch, anvil mock refresh |
| `tests.md` | `test/**` | Abstract `DSCEngineTest` scaffold + mock families (`ERC20DecimalsMock`, `MockDSC*` failure variants), mirrored constants, path-driven Makefile layout |
| `invariants.md` | `test/invariant/**` | Layered on `tests.md`: paired `FailOnRevert` / `ContinueOnRevert` runners, `BaseHandler` + `EnumerableSet` user set, `boundSilent` input bounding |
