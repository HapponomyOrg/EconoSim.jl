# SuMSy (Sustainable Money System) mechanics.
#
# Guaranteed income creates money; demurrage destroys it. Tiers are stored as
# integer spans and permyriad rates, so no Interval or Percentage types leak
# into the core.

"""
    DemTiers(spans, rates)

A piecewise demurrage schedule. `spans[i]` is the width of tier `i` (the last
span is `typemax(Money)`); `rates[i]` is its permyriad rate.
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
        rates[i] = permyriad(ordered[i][2])
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
                telo_value += Money(div((income.value - total_dem.value) * PERMYRIAD,
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

    demurrage = MONEY_ZERO
    for i in eachindex(tiers.rates)
        remaining <= MONEY_ZERO && break
        span = tiers.spans[i]
        amount = span == typemax(Money) ? remaining : min(remaining, span)
        demurrage += apply_rate(amount, tiers.rates[i])
        remaining -= amount
    end

    demurrage = Money(div(demurrage.value * timerange, interval))
    return Money(demurrage.value * sign)
end

"""
    calculate_adjustments(balance, sumsy, gi_eligible, dem_free, interval, timerange, allow_negative)

Return `(guaranteed_income, demurrage)` for one adjustment.
"""
function calculate_adjustments(balance::Money, sumsy::SuMSy, gi_eligible::Bool,
                               dem_free::Money, interval::Int, timerange::Int,
                               allow_negative::Bool)
    guaranteed_income = gi_eligible ?
        Money(div(sumsy.guaranteed_income.value * timerange, interval)) : MONEY_ZERO
    demurrage = calculate_time_range_demurrage(balance, sumsy.demurrage, dem_free,
                                               interval, timerange, allow_negative)
    return guaranteed_income, demurrage
end

"""
    SuMSyAccount

A concrete account with a SuMSy deposit. No models, agents, or function fields.
"""
mutable struct SuMSyAccount
    balance::Balance
    sumsy::SuMSy
    gi_eligible::Bool
    dem_free::Money
    last_adjustment::Int64
    sumsy_interval::Int
    transactional::Bool
    allow_negative_demurrage::Bool
end

function SuMSyAccount(sumsy::SuMSy; gi_eligible::Bool = true,
                      dem_free::Money = sumsy.dem_free,
                      interval::Integer = 30,
                      transactional::Bool = false,
                      allow_negative::Bool = true,
                      allow_negative_demurrage::Bool = false)
    balance = Balance()
    allow_negative && typemin_asset!(balance, SUMSY_DEPOSIT)
    return SuMSyAccount(balance, sumsy, gi_eligible, dem_free, 0, Int(interval),
                        transactional, allow_negative_demurrage)
end

@inline asset_value(account::SuMSyAccount) =
    asset_value(account.balance, SUMSY_DEPOSIT)

"""
    adjust!(account, timestamp) -> (guaranteed_income, demurrage)

Apply guaranteed income and demurrage since the last adjustment.
"""
function adjust!(account::SuMSyAccount, timestamp::Integer)
    elapsed = Int(timestamp) - Int(account.last_adjustment)
    elapsed <= 0 && return (MONEY_ZERO, MONEY_ZERO)

    balance = asset_value(account)
    guaranteed_income, demurrage = calculate_adjustments(
        balance, account.sumsy, account.gi_eligible, account.dem_free,
        account.sumsy_interval, elapsed, account.allow_negative_demurrage)

    net = guaranteed_income - demurrage
    if net != MONEY_ZERO
        book_asset!(account.balance, SUMSY_DEPOSIT, net; timestamp = timestamp)
    else
        account.balance.last_transaction = Int64(timestamp)
    end

    account.last_adjustment = Int64(timestamp)
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
export SuMSyAccount, adjust!, calculate_sumsy_deposit
