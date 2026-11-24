# Primitive parity suite

Compares main `EconoSim` against `EconoSimCore` on deterministic primitives.
Every monetary value is compared as its `10^-4` scaled integer, so a difference
of one last decimal fails the test.

## Run

```bash
julia --project=test/parity test/parity/runtests.jl
```

The environment in `Project.toml` resolves both packages from this checkout via
`[sources]`; it does not use the registered EconoSim release.

## Coverage

| Area | Checks |
|---|---|
| `telo` | flat and tiered schedules, zero and large incomes |
| Demurrage | tiered, demurrage-free buffer, negative balances, partial intervals |
| SuMSy deposit | 1, 30, and 500 periods, including negative demurrage |
| SuMSy accounts | interval-aligned adjustments, partial intervals, transactional accounts, GI-ineligible accounts, demurrage-free buffer |
| Balance | asset/liability booking, equity, transfers, minimum rejection, clearing |
| Debt | installments, full lifecycle, shortfall spreading, bank and non-bank loans, several rates |

## Difference found

The suite exposed one real semantic mismatch: legacy `SingleSuMSyBalance` only
adjusts a non-transactional account at full `sumsy_interval` multiples, and a
call at a partial timestamp still advances `last_adjustment` (the partial period
is skipped). Core `SuMSyAccount.adjust!` used to prorate every elapsed period.
Core now matches legacy.

## Not covered yet

Stochastic model paths. Those need a scripted RNG and identical draw order; see
`sim.wasm/docs/plans/2026-11-24-core-hardening.md` (WS4b).
