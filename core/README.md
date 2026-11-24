# EconoSimCore

Dependency-free economic simulation primitives extracted from `EconoSim.jl`:
integer fixed-point money, concrete balance sheets, the SuMSy money system,
debt contracts, and a deterministic RNG.

The wasm ABI, build, and TypeScript generation live in
`sim.wasm/wasm/`; this package contains no wasm tooling or WasmTarget
dependency.

## What is here

| File | Contents |
|---|---|
| `src/money.jl` | `Money` (Int64 × 10^4), ppm rates, overflow-safe `apply_rate`, `split_amount` |
| `src/rng.jl` | Explicit xorshift64 `Rng`; no global RNG |
| `src/entries.jl` | `Entry` / `Side` enums; fixed ledger slots |
| `src/balance.jl` | Concrete double-entry `Balance` with integer ledgers and no property bags |
| `src/sumsy.jl` | `DemTiers`, `SuMSy`, `telo`, demurrage, `SuMSyAccount` |
| `src/debt.jl` | `Debt`, `borrow`, `process_debt!` |

There are no Agents.jl, DataFrames, UUIDs, Intervals, or FixedPointDecimals
dependencies. Money is exact integer fixed point; rates are parts per million.

## Test

```bash
julia --project=core -e 'using Pkg; Pkg.test()'
```

## Design notes

- `Money` is `Int64` scaled by `10^4` (currency × 10,000); one currency unit is
  `10_000`. This is enough for realistic national aggregates and avoids the
  Int128 division gap in the wasm backend.
- Rates are `Int64` parts per million (rate × 1,000,000).
- `Balance` has one `Money` slot per `Entry` on each side. Booking an asset
  increases equity; booking a liability decreases it, preserving
  `sum(assets) == sum(liabilities)`.
- Demurrage tiers are stored as integer spans + ppm rates, replacing
  `Intervals`/`Percentage`.
- The RNG is passed explicitly through every stochastic step. Seeds are stable
  across Julia versions.
- `SuMSyAccount` is a concrete plain struct; the high-level `EconoSim` actor
  types will adapt to it in a later phase.

## Not here yet

- `MoneySimCore` (population, transactions, taxes, government, GDP, metrics).
- The Agents.jl adapter in the root `EconoSim` package.

The wasm build package is `sim.wasm/wasm/`. See
`sim.wasm/docs/plans/` in the workspace for the cross-repo plan.
