# SuMSy (Sustainable Money System) mechanics.
#
# Guaranteed income creates money; demurrage destroys it. Tiers are stored as
# integer spans and ppm rates, so no Interval or Percentage types leak
# into the core.

"""
    DemTiers(spans, rates)

A piecewise demurrage schedule. `spans[i]` is the width of tier `i` (the last
span is `typemax(Money)`); `rates[i]` is its ppm rate.
"""
struct DemTiers
    spans::Vector{Money}
    rates::Vector{Int64}
end

"""
    make_tiers(settings) -> DemTiers

Build tiers from `(lower_bound, rate)` pairs. The first pair starts at 0, each
pair's rate applies until the next lower bound, and the last rate is unbounded.
This matches MoneySim's `make_tiers` semantics.
"""
function make_tiers(settings::AbstractVector{<:Tuple{<:Real,<:Real}})
    isempty(settings) && throw(ArgumentError("at least one demurrage tier is required"))

    ordered = sort(collect(settings); by = first)
    spans = Vector{Money}(undef, length(ordered))
    rates = Vector{Int64}(undef, length(ordered))

    for i in eachindex(ordered)
        lower = money(ordered[i][1])
        upper = i == length(ordered) ? typemax(Money) : money(ordered[i + 1][1])
        spans[i] = upper == typemax(Money) ? typemax(Money) : upper - lower
        rates[i] = ppm(ordered[i][2])
    end

    return DemTiers(spans, rates)
end

make_tiers(demurrage_rate::Real) = make_tiers([(0.0, demurrage_rate)])

const NO_DEM_TIERS = make_tiers([(0.0, 0.0)])

"""
    SuMSy(guaranteed_income, demurrage_free, demurrage)

The money-system parameters: a periodic guaranteed income, a demurrage-free
buffer, and a demurrage schedule.
"""
struct SuMSy
    guaranteed_income::Money
    demurrage::DemTiers
    dem_free::Money
end

SuMSy(guaranteed_income::Real, dem_free::Real, demurrage::Real) =
    SuMSy(money(guaranteed_income), make_tiers(demurrage), money(dem_free))

SuMSy(guaranteed_income::Real, dem_free::Real,
      demurrage::AbstractVector{<:Tuple{<:Real,<:Real}}) =
    SuMSy(money(guaranteed_income), make_tiers(demurrage), money(dem_free))

"""
    telo(income, demurrage, dem_free = 0) -> Money

The equilibrium balance at which guaranteed income equals demurrage. For a flat
rate `d`, this is `income / d` plus the demurrage-free buffer.
"""
function telo(income::Money, demurrage::DemTiers, dem_free::Money = MONEY_ZERO)
    total_dem = MONEY_ZERO
    telo_value = MONEY_ZERO

    for i in eachindex(demurrage.rates)
        span = demurrage.spans[i]
        rate_pm = demurrage.rates[i]

        if span == typemax(Money) || total_dem + apply_rate(span, rate_pm) > income
            if rate_pm != 0
                telo_value += Money(div((income.value - total_dem.value) * RATE_SCALE,
                                        rate_pm))
            else
                telo_value = typemax(Money)
            end
            break
        else
            telo_value += span
            total_dem += apply_rate(span, rate_pm)
        end
    end

    return telo_value + dem_free
end

telo(income::Real, demurrage::Real, dem_free::Real = 0.0) =
    telo(money(income), make_tiers(demurrage), money(dem_free))

telo(income::Real, demurrage::AbstractVector{<:Tuple{<:Real,<:Real}},
     dem_free::Real = 0.0) =
    telo(money(income), make_tiers(demurrage), money(dem_free))

telo(sumsy::SuMSy) = telo(sumsy.guaranteed_income, sumsy.demurrage, sumsy.dem_free)

"""
    calculate_time_range_demurrage(balance, tiers, dem_free, interval, timerange, allow_negative)

Demurrage owed over `timerange` periods of length `interval`.

Each tier's product is evaluated in `Float64` and only the final total is
rounded to `Money`, mirroring main EconoSim's `Currency * Percentage`
arithmetic. Legacy accumulates those products as floats, so a half-unit tie
rounds with the float error of the operands rather than exactly to even.
Reproducing that here keeps demurrage identical to legacy at every tie, which
matters once a balance is adjusted thousands of times.
"""
function calculate_time_range_demurrage(balance::Money, tiers::DemTiers,
                                        dem_free::Money, interval::Int,
                                        timerange::Int, allow_negative::Bool)
    if balance <= MONEY_ZERO && !allow_negative
        return MONEY_ZERO
    end

    sign = balance < MONEY_ZERO ? -1 : 1
    remaining = balance > MONEY_ZERO ? balance - dem_free : balance
    remaining = Money(remaining.value * sign)

    demurrage = 0.0
    for i in eachindex(tiers.rates)
        remaining <= MONEY_ZERO && break
        span = tiers.spans[i]
        amount = span == typemax(Money) ? remaining : min(remaining, span)
        demurrage += currency(amount) *
                     (Float64(tiers.rates[i]) / Float64(RATE_SCALE))
        remaining -= amount
    end

    demurrage *= Float64(timerange) / Float64(interval) * Float64(sign)
    return Money(round(Int64, demurrage * SCALE))
end

"""
    calculate_adjustments(balance, sumsy, gi_eligible, dem_free, interval, timerange, allow_negative)

Return `(guaranteed_income, demurrage)` for one adjustment.
"""
function calculate_adjustments(balance::Money, sumsy::SuMSy, gi_eligible::Bool,
                               dem_free::Money, interval::Int, timerange::Int,
                               allow_negative::Bool)
    guaranteed_income = gi_eligible ?
        Money(div_round_nearest(sumsy.guaranteed_income.value * timerange,
                                interval)) : MONEY_ZERO
    demurrage = calculate_time_range_demurrage(balance, sumsy.demurrage, dem_free,
                                               interval, timerange, allow_negative)
    return guaranteed_income, demurrage
end

"""
    SuMSyAccrual

Guaranteed income settled so far within the current SuMSy period. Guaranteed
income is rounded on its running total, so a full period always pays exactly
the period's guaranteed income regardless of how often it is settled.

- `gi_steps`: steps settled since the period started.
- `gi_booked`: guaranteed income booked for those steps.
"""
mutable struct SuMSyAccrual
    gi_steps::Int
    gi_booked::Money
end

SuMSyAccrual() = SuMSyAccrual(0, MONEY_ZERO)
Base.copy(accrual::SuMSyAccrual) =
    SuMSyAccrual(accrual.gi_steps, accrual.gi_booked)

"""
    check_granularity(granularity, sumsy_interval)

A granularity must be at least 1 and at most the SuMSy period. A longer
granularity could charge more demurrage in one settlement than the balance holds.
"""
function check_granularity(granularity::Int, sumsy_interval::Int)
    granularity >= 1 ||
        throw(ArgumentError("granularity must be at least 1, got $granularity"))
    granularity <= sumsy_interval ||
        throw(ArgumentError("granularity must not exceed the SuMSy period ($sumsy_interval), got $granularity"))
    return granularity
end

"""
    SuMSyAccount

A concrete account with a SuMSy deposit. No models, agents, or function fields.
Guaranteed income and demurrage settle every `granularity` steps; each
settlement applies `granularity / sumsy_interval` of the period's rates.
"""
mutable struct SuMSyAccount
    balance::Balance
    sumsy::SuMSy
    gi_eligible::Bool
    dem_free::Money
    last_adjustment::Int64
    sumsy_interval::Int
    granularity::Int
    allow_negative_demurrage::Bool
    accrual::SuMSyAccrual
end

function SuMSyAccount(sumsy::SuMSy; gi_eligible::Bool = true,
                      dem_free::Money = sumsy.dem_free,
                      interval::Integer = 30,
                      granularity::Integer = interval,
                      allow_negative::Bool = true,
                      allow_negative_demurrage::Bool = false)
    balance = Balance()
    allow_negative && typemin_asset!(balance, SUMSY_DEPOSIT)
    return SuMSyAccount(balance, sumsy, gi_eligible, dem_free, 0, Int(interval),
                        check_granularity(Int(granularity), Int(interval)),
                        allow_negative_demurrage, SuMSyAccrual())
end

@inline asset_value(account::SuMSyAccount) =
    asset_value(account.balance, SUMSY_DEPOSIT)
@inline get_granularity(account::SuMSyAccount) = account.granularity

"""
    set_granularity!(account, granularity)

Change the settlement granularity. Settle the account first
(`adjust!`), otherwise the granules that have elapsed are settled with the new
granularity.
"""
function set_granularity!(account::SuMSyAccount, granularity::Integer)
    account.granularity =
        check_granularity(Int(granularity), account.sumsy_interval)
    return account
end

"""
    book_settlement!(balance, entry, amount, timestamp)

Book a net settlement (guaranteed income - demurrage) on a SuMSy entry. A
positive settlement is always booked, even on an entry below its minimum. A
negative settlement that would take the entry below its minimum books nothing
and throws, so a settlement is never skipped silently.
"""
function book_settlement!(balance::Balance, entry::Entry, amount::Money,
                          timestamp::Integer)
    booked = book_asset!(balance, entry, amount; timestamp = timestamp,
                         skip_check = amount >= MONEY_ZERO)
    booked || error("settling $(currency(amount)) would take SuMSy entry below its minimum; nothing was booked")
    return nothing
end

"""
    _settle_granules(base, granules, granularity, interval, income, gi_eligible,
                     tiers, dem_free, allow_negative, accrual) -> (gi, demurrage)

Settle `granules` granules on `base`, compounding each one. `accrual` is
updated in place. This is the core of `accrue`, kept in its own function so the
loan and settlement loops stay readable.
"""
function _settle_granules(base::Money, granules::Int, granularity::Int,
                          interval::Int, income::Money, gi_eligible::Bool,
                          tiers::DemTiers, dem_free::Money,
                          allow_negative::Bool, accrual::SuMSyAccrual)
    total_income = MONEY_ZERO
    total_demurrage = MONEY_ZERO

    for _ in 1:granules
        demurrage = calculate_time_range_demurrage(base, tiers, dem_free,
                                                   interval, granularity,
                                                   allow_negative)
        guaranteed_income = MONEY_ZERO

        if gi_eligible
            accrual.gi_steps += granularity
            due = Money(div_round_nearest(income.value * accrual.gi_steps,
                                          interval))
            guaranteed_income = due - accrual.gi_booked
            accrual.gi_booked = due

            if mod(accrual.gi_steps, interval) == 0
                # Full periods pay exactly; restart the running total.
                accrual.gi_steps = 0
                accrual.gi_booked = MONEY_ZERO
            end
        end

        base += guaranteed_income - demurrage
        total_income += guaranteed_income
        total_demurrage += demurrage
    end

    return total_income, total_demurrage
end

"""
    accrue_sumsy(base, accrual, last_adjustment, timestamp, granularity,
                 interval, income, gi_eligible, tiers, dem_free,
                 allow_negative) -> (gi, demurrage, accrual, last_adjustment)

Stateless form of `accrue`: settle all complete granules up to `timestamp` for a
raw balance and accrual state. Used by `MoneySimCore`, which stores per-actor
balances in flat arrays instead of `SuMSyAccount` objects.
"""
function accrue_sumsy(base::Money, accrual::SuMSyAccrual, last_adjustment::Integer,
                      timestamp::Integer, granularity::Int, interval::Int,
                      income::Money, gi_eligible::Bool, tiers::DemTiers,
                      dem_free::Money, allow_negative::Bool)
    granules = max(0, div(Int(timestamp) - Int(last_adjustment), granularity))
    updated = copy(accrual)

    granules == 0 &&
        return (MONEY_ZERO, MONEY_ZERO, updated, Int(last_adjustment))

    guaranteed_income, demurrage = _settle_granules(
        base, granules, granularity, interval, income, gi_eligible, tiers,
        dem_free, allow_negative, updated)

    return (guaranteed_income, demurrage, updated,
            Int(last_adjustment) + granules * granularity)
end

"""
    accrue(account, timestamp) -> (guaranteed_income, demurrage, accrual, last_adjustment)

Calculate the guaranteed income and demurrage to book for all complete granules
up to `timestamp`. Nothing is changed. Steps after the last complete granule
carry over to the next settlement.
"""
function accrue(account::SuMSyAccount, timestamp::Integer)
    return accrue_sumsy(asset_value(account), account.accrual,
                        account.last_adjustment, timestamp,
                        account.granularity, account.sumsy_interval,
                        account.sumsy.guaranteed_income, account.gi_eligible,
                        account.sumsy.demurrage, account.dem_free,
                        account.allow_negative_demurrage)
end

"""
    calculate_adjustments(account, timestamp) -> (guaranteed_income, demurrage)

The settlement `adjust!` would book at `timestamp`, without changing the account.
"""
function calculate_adjustments(account::SuMSyAccount, timestamp::Integer)
    guaranteed_income, demurrage, _, _ = accrue(account, timestamp)
    return guaranteed_income, demurrage
end

"""
    adjust!(account, timestamp) -> (guaranteed_income, demurrage)

Settle all complete granules up to `timestamp` and book the net settlement.
"""
function adjust!(account::SuMSyAccount, timestamp::Integer)
    guaranteed_income, demurrage, accrual, last_adjustment =
        accrue(account, timestamp)

    book_settlement!(account.balance, SUMSY_DEPOSIT,
                     guaranteed_income - demurrage, timestamp)

    account.accrual = accrual
    account.last_adjustment = last_adjustment
    return guaranteed_income, demurrage
end

"""
    calculate_sumsy_deposit(sumsy, periods, start_amount = 0; allow_negative_demurrage = false)

The deposit after `periods` of guaranteed income and demurrage, without
transactions. Used to validate the `telo` equilibrium.
"""
function calculate_sumsy_deposit(sumsy::SuMSy, periods::Int,
                                 start_amount::Money = MONEY_ZERO;
                                 allow_negative_demurrage::Bool = false)
    amount = start_amount
    for _ in 1:periods
        guaranteed_income, demurrage = calculate_adjustments(
            amount, sumsy, true, sumsy.dem_free, 1, 1, allow_negative_demurrage)
        amount += guaranteed_income - demurrage
    end
    return amount
end

export DemTiers, make_tiers, NO_DEM_TIERS, SuMSy, telo
export calculate_time_range_demurrage, calculate_adjustments
export SuMSyAccount, SuMSyAccrual, adjust!, calculate_sumsy_deposit
export check_granularity, get_granularity, set_granularity!, book_settlement!, accrue
export accrue_sumsy
