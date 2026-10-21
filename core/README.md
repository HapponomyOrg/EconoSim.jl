# EconoSimCore

Dependency-free economic simulation primitives extracted from `EconoSim.jl`,
designed to compile to WebAssembly with
[WasmTarget.jl](https://github.com/GroupTherapyOrg/WasmTarget.jl).

This is Phase 1 of the WASM-ready core plan. The canonical document is
[`MoneySim.jl/docs/plans/2026-10-21-wasm-ready-core.md`](https://github.com/HapponomyOrg/MoneySim.jl/blob/main/docs/plans/2026-10-21-wasm-ready-core.md)
in the workspace (it will move with the MoneySim pull request).

## What is here

| File | Contents |
|---|---|
| `src/money.jl` | `Money` (Int64 × 10^4), permyriad rates, overflow-safe `apply_rate`, `split_amount` |
| `src/rng.jl` | Explicit xorshift64 `Rng`; no global RNG |
| `src/entries.jl` | `Entry` / `Side` enums; fixed ledger slots |
| `src/balance.jl` | Concrete double-entry `Balance` with integer ledgers and no property bags |
| `src/sumsy.jl` | `DemTiers`, `SuMSy`, `telo`, demurrage, `SuMSyAccount` |
| `src/debt.jl` | `Debt`, `borrow`, `process_debt!` |

There are no Agents.jl, DataFrames, UUIDs, Intervals, or FixedPointDecimals
dependencies. Money is exact integer fixed point; rates are permyriad.

## Test

```bash
julia --project=core -e 'using Pkg; Pkg.test()'
```

## Wasm compile smoke test

The smoke test compiles a SuMSy account and a balance booking kernel. It uses
the `sim.wasm/julia` environment because that is where WasmTarget is installed:

```bash
julia --project=../sim.wasm/julia core/test/wasm_smoke.jl /tmp/econosim_core_smoke.wasm
```

Then instantiate it with Node (WasmGC, Node 20+):

```bash
node core/test/wasm_smoke.mjs /tmp/econosim_core_smoke.wasm
```

The module has no imports. `sumsy_smoke(10)` returns the same scaled value as
the native Julia test, which is the first native↔wasm parity check for the
core.

## Design notes

- `Money` is `Int64` scaled by `10^4` (currency × 10,000); one currency unit is
  `10_000`. This is enough for realistic national aggregates and avoids the
  Int128 division gap in the wasm backend.
- Rates are `Int64` permyriad (rate × 10,000).
- `Balance` has one `Money` slot per `Entry` on each side. Booking an asset
  increases equity; booking a liability decreases it, preserving
  `sum(assets) == sum(liabilities)`.
- Demurrage tiers are stored as integer spans + permyriad rates, replacing
  `Intervals`/`Percentage`.
- The RNG is passed explicitly through every stochastic step. Seeds are stable
  across Julia versions.
- `SuMSyAccount` is a concrete plain struct; the high-level `EconoSim` actor
  types will adapt to it in a later phase.

## Not here yet

- `MoneySimCore` (population, transactions, taxes, government, GDP, metrics).
- The wasm ABI (`engine_*` / `result_*` / schema generation).
- The Agents.jl adapter in the root `EconoSim` package.

Those are later phases in the plan.
