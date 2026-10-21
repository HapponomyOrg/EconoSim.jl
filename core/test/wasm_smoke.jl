# WasmTarget smoke test for EconoSimCore.
#
# Run with a project that has WasmTarget installed, for example:
#   julia --project=../sim.wasm/julia core/test/wasm_smoke.jl
#
# This is deliberately a build check, not part of the package test target:
# WasmTarget is not a dependency of EconoSimCore.

using WasmTarget

include(joinpath(@__DIR__, "..", "src", "EconoSimCore.jl"))
using .EconoSimCore

"""
A representative kernel: a SuMSy account with guaranteed income, demurrage,
and no transactions. Returns the final scaled deposit.
"""
function sumsy_smoke(periods::Int)::Int64
    account = SuMSyAccount(SuMSy(2_000.0, 0.0, 0.01); interval = 30)
    for period in 1:periods
        adjust!(account, period * 30)
    end
    return asset_value(account).value
end

function balance_smoke(amount::Int64)::Int64
    balance = Balance()
    book_asset!(balance, SUMSY_DEPOSIT, Money(amount))
    book_liability!(balance, DEBT, Money(div(amount, 2)))
    return assets_value(balance).value
end

bytes = compile_multi([
    (sumsy_smoke, (Int,)),
    (balance_smoke, (Int64,)),
]; optimize = true)

out = isempty(ARGS) ? joinpath(tempdir(), "econosim_core_smoke.wasm") : ARGS[1]
write(out, bytes)
println("Wrote ", out, " (", length(bytes), " bytes)")
