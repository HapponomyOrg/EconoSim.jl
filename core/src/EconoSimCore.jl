"""
    EconoSimCore

Dependency-free economic simulation primitives that compile to WebAssembly:
integer fixed-point money, concrete balance sheets, the SuMSy money system,
debt contracts, and a deterministic RNG.

This module is deliberately free of Agents.jl, DataFrames, UUIDs, Intervals,
and `FixedPointDecimals`. The high-level `EconoSim` package remains the
Agents.jl-facing API and can delegate to this core.

All money is `Money` (Int64 scaled by 10^4). All rates are `Int64` in parts
per million (rate × 10^6). See `docs/plans/2026-10-21-wasm-ready-core.md`.
"""
module EconoSimCore

include("money.jl")
include("rng.jl")
include("entries.jl")
include("balance.jl")
include("sumsy.jl")
include("debt.jl")

end
