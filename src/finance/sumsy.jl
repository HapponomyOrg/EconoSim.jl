using DataStructures
using Intervals
using UUIDs
using Todo

SUMSY_DEP = BalanceEntry("SuMSy deposit")
SUMSY_DEBT = BalanceEntry("SuMSy debt")

DemTiers = Vector{Tuple{Interval, Percentage}}
DemSettings = Union{DemTiers, Vector{<: Tuple{Real, Real}}, Real}

abstract type SuMSyBalance{C <: FixedDecimal} <: AbstractBalance{C} end

set_last_transaction!(sumsy_balance::SuMSyBalance, timestamp::Int) = set_last_transaction!(sumsy_balance.balance, timestamp)
get_last_transaction(sumsy_balance::SuMSyBalance) = get_last_transaction(sumsy_balance.balance)

has_asset(sumsy_balance::SuMSyBalance, entry::BalanceEntry) = has_asset(get_balance(sumsy_balance), entry)
has_liability(sumsy_balance::SuMSyBalance, entry::BalanceEntry) = has_liability(get_balance(sumsy_balance), entry)

clear!(sumsy_balance::SuMSyBalance) = clear!(get_balance(sumsy_balance))

min_balance!(sumsy_balance::SuMSyBalance,
                entry::BalanceEntry,
                type::EntryType,
                amount::Real = 0) = min_balance!(get_balance(sumsy_balance), entry, type, amount)
typemin_balance!(sumsy_balance::SuMSyBalance,
                    entry::BalanceEntry,
                    type::EntryType) = typemin_balance!(get_balance(sumsy_balance), entry, type)

min_asset!(sumsy_balance::SuMSyBalance, entry::BalanceEntry, amount::Real = 0) = min_asset!(get_balance(sumsy_balance), entry, amount)
typemin_asset!(sumsy_balance::SuMSyBalance, entry::BalanceEntry) = typemin_asset!(get_balance(sumsy_balance), entry)

min_liability!(sumsy_balance::SuMSyBalance, entry::BalanceEntry, amount::Real = 0) = min_liability!(get_balance(sumsy_balance), entry, amount)
typemin_liability!(sumsy_balance::SuMSyBalance, entry::BalanceEntry) = typemin_liability!(get_balance(sumsy_balance), entry)

min_balance(sumsy_balance::SuMSyBalance, entry::BalanceEntry, type::EntryType) = min_balance(get_balance(sumsy_balance), entry, type)
min_asset(sumsy_balance::SuMSyBalance, entry::BalanceEntry) = min_asset(get_balance(sumsy_balance), entry)
min_liability(sumsy_balance::SuMSyBalance, entry::BalanceEntry) = min_liability(get_balance(sumsy_balance), entry)


validate(sumsy_balance::SuMSyBalance) = validate(get_balance(sumsy_balance))
asset_value(sumsy_balance::SuMSyBalance, entry::BalanceEntry) = asset_value(get_balance(sumsy_balance), entry)
liability_value(sumsy_balance::SuMSyBalance, entry::BalanceEntry) = liability_value(get_balance(sumsy_balance), entry)
assets(sumsy_balance::SuMSyBalance) = assets(get_balance(sumsy_balance))
liabilities(sumsy_balance::SuMSyBalance) = liabilities(get_balance(sumsy_balance))
assets_value(sumsy_balance::SuMSyBalance) = assets_value(get_balance(sumsy_balance))
liabilities_value(sumsy_balance::SuMSyBalance) = liabilities_value(get_balance(sumsy_balance))
liabilities_net_value(sumsy_balance::SuMSyBalance) = liabilities_net_value(get_balance(sumsy_balance))
equity(sumsy_balance::SuMSyBalance) = equity(get_balance(sumsy_balance))

book_asset!(sumsy_balance::SuMSyBalance,
            entry::BalanceEntry,
            amount::Real;
            timestamp::Int = get_last_adjustment(sumsy_balance),
            set_to_value = false) = book_asset!(get_balance(sumsy_balance),
                                                entry,
                                                amount,
                                                timestamp = timestamp,
                                                set_to_value = set_to_value)
book_liability!(sumsy_balance::SuMSyBalance,
                entry::BalanceEntry,
                amount::Real;
                timestamp::Int = get_last_adjustment(sumsy_balance),
                set_to_value = false) = book_liability!(get_balance(sumsy_balance),
                                                            entry,
                                                            amount,
                                                            set_to_value = set_to_value,
                                                            timestamp = timestamp)
transfer!(sumsy_balance1::SuMSyBalance,
            type1::EntryType,
            entry1::BalanceEntry,
            sumsy_balance2::SuMSyBalance,
            type2::EntryType,
            entry2::BalanceEntry,
            amount::Real;
            timestamp::Int = max(get_last_adjustment(sumsy_balance1), get_last_adjustment(sumsy_balance2))) =
                transfer!(get_balance(sumsy_balance1),
                            type1,
                            entry1,
                            get_balance(sumsy_balance2),
                            type2,
                            entry2,
                            amount,
                            timestamp = timestamp)
transfer!(sumsy_balance1::SuMSyBalance,
                type1::EntryType,
                sumsy_balance2::SuMSyBalance,
                type2::EntryType,
                entry::BalanceEntry,
                amount::Real;
                timestamp::Int = max(get_last_adjustment(sumsy_balance1), get_last_adjustment(sumsy_balance2))) =
                    transfer!(get_balance(sumsy_balance1),
                                type1,
                                get_balance(sumsy_balance2),
                                type2,
                                entry,
                                amount,
                                timestamp = timestamp)
transfer_asset!(sumsy_balance1::SuMSyBalance,
                sumsy_balance2::SuMSyBalance,
                entry::BalanceEntry,
                amount::Real;
                timestamp::Int = max(get_last_adjustment(sumsy_balance1), get_last_adjustment(sumsy_balance2))) =
                    transfer_asset!(get_balance(sumsy_balance1),
                                    get_balance(sumsy_balance2),
                                    entry,
                                    amount,
                                    timestamp = timestamp)
transfer_asset!(sumsy_balance1::SuMSyBalance,
                entry1::BalanceEntry,
                sumsy_balance2::SuMSyBalance,
                entry2::BalanceEntry,
                amount::Real;
                timestamp::Int = max(get_last_adjustment(sumsy_balance1), get_last_adjustment(sumsy_balance2))) =
                    transfer_asset!(get_balance(sumsy_balance1),
                                    entry1,
                                    get_balance(sumsy_balance2),
                                    entry2,
                                    amount,
                                    timestamp = timestamp)
transfer_liability!(sumsy_balance1::SuMSyBalance,
                    sumsy_balance2::SuMSyBalance,
                    entry::BalanceEntry,
                    amount::Real;
                    timestamp::Int = max(get_last_adjustment(sumsy_balance1), get_last_adjustment(sumsy_balance2))) =
                        transfer_liability!(get_balance(sumsy_balance1),
                                            get_balance(sumsy_balance2),
                                            entry,
                                            amount,
                                            timestamp = timestamp)
transfer_liability!(sumsy_balance1::SuMSyBalance,
                    entry1::BalanceEntry,
                    sumsy_balance2::SuMSyBalance,
                    entry2::BalanceEntry,
                    amount::Real;
                    timestamp::Int = max(get_last_adjustment(sumsy_balance1), get_last_adjustment(sumsy_balance2))) =
                        transfer_liability!(get_balance(sumsy_balance1),
                                            entry1,
                                            get_balance(sumsy_balance2),
                                            entry2,
                                            amount,
                                            timestamp = timestamp)
queue_transfer!(sumsy_balance1::SuMSyBalance,
                type1::EntryType,
                entry1::BalanceEntry,
                sumsy_balance2::SuMSyBalance,
                type2::EntryType,
                entry2::BalanceEntry,
                amount::Real;
                timestamp::Int = max(get_last_adjustment(sumsy_balance1), get_last_adjustment(sumsy_balance2))) =
                    queue_transfer!(get_balance(sumsy_balance1),
                                    type1,
                                    entry1,
                                    get_balance(sumsy_balance2),
                                    type2,
                                    entry2,
                                    amount,
                                    timestamp = timestamp)
queue_asset_transfer!(sumsy_balance1::SuMSyBalance,
                        entry1::BalanceEntry,
                        sumsy_balance2::SuMSyBalance,
                        entry2::BalanceEntry,
                        amount::Real;
                        timestamp::Int = max(get_last_adjustment(sumsy_balance1), get_last_adjustment(sumsy_balance2))) =
                            queue_asset_transfer!(get_balance(sumsy_balance1),
                                                    entry1,
                                                    get_balance(sumsy_balance2),
                                                    entry2,
                                                    amount)
queue_asset_transfer!(sumsy_balance1::SuMSyBalance,
                        sumsy_balance2::SuMSyBalance,
                        entry::BalanceEntry,
                        amount::Real;
                        timestamp::Int = max(get_last_adjustment(sumsy_balance1), get_last_adjustment(sumsy_balance2))) =
                            queue_asset_transfer!(get_balance(sumsy_balance1),
                                                    get_balance(sumsy_balance2),
                                                    entry,
                                                    amount,
                                                    timestamp = timestamp)
queue_liability_transfer!(sumsy_balance1::SuMSyBalance,
                            entry1::BalanceEntry,
                            sumsy_balance2::SuMSyBalance,
                            entry2::BalanceEntry,
                            amount::Real;
                            timestamp::Int = max(get_last_adjustment(sumsy_balance1), get_last_adjustment(sumsy_balance2))) =
                                queue_liability_transfer!(get_balance(sumsy_balance1),
                                                            entry1,
                                                            get_balance(sumsy_balance2),
                                                            entry2,
                                                            amount,
                                                            timestamp = timestamp)
queue_liability_transfer!(sumsy_balance1::SuMSyBalance,
                            sumsy_balance2::SuMSyBalance,
                            entry::BalanceEntry,
                            amount::Real;
                            timestamp::Int = max(get_last_adjustment(sumsy_balance1), get_last_adjustment(sumsy_balance2))) =
                                queue_liability_transfer!(get_balance(sumsy_balance1),
                                                            get_balance(sumsy_balance2),
                                                            entry,
                                                            amount,
                                                            timestamp = timestamp)

execute_transfers!(sumsy_balance::SuMSyBalance) = execute_transfers!(get_balance(sumsy_balance))

"""
    struct SuMSy

Representation of the parameters of a SuMSy implementation.

* id: a unique id.
* guaranteed_income: the periodical guaranteed income.
* dem_free_buffer: the demurrage free buffer which is allocated to all accounts which have a right to a guaranteed income.
* dem_settings: the demurrage tiers. This is a list of tuples consisting of a lower bound and a demurrage percentage. The demurrage percentage is applied to the amounts above the lower bound up to the the next higher lower bound. If the demurrage free buffer of an account is larger than 0, all bounds are shifted up with this amount and no demurrage is applied to the amount up to the available demurrage free buffer.
The lower bound of the first tuple is always set to 0.
* interval: the interval after which demurrage is calculated and guaranteed income is dposited. If this interval is smaller than the period, partial demurrage and guaranteed income are applied. The scaling factor being equal to interval/period.
* seed: the amount whith which new accounts start.
* guaranteed_income_comment: The transaction comment for guaranteed income bookings.
* demurrage_comment: The transaction comment for demurrage bookings.
* net_income_comment: The transaction comment for net income bookings. These transactions combine demurrage and guaranteed income in one transaction.
* dep_entry: The balance entry used for depositing GI.
"""
struct SuMSyIncome{C <: FixedDecimal}
    seed::C
    guaranteed_income::C
    SuMSyIncome(seed::Real, guaranteed_income::Real) = new{Currency}(seed, guaranteed_income)
end

struct SuMSyDemurrage{C <: FixedDecimal}
    dem_free::C
    dem_tiers::DemTiers
    SuMSyDemurrage(dem_free::Real, dem_tiers::DemTiers) = new{Currency}(dem_free, dem_tiers)
end

struct SuMSy{C <: FixedDecimal}
    income::SuMSyIncome{C}
    demurrage::SuMSyDemurrage{C}
end

function SuMSy(guaranteed_income::Real,
                dem_free::Real,
                dem_settings::DemSettings;
                seed::Real = 0)
    dem_tiers = make_tiers(dem_settings)
    income = SuMSyIncome(seed, guaranteed_income)
    demurrage = SuMSyDemurrage(dem_free, dem_tiers)

    return SuMSy(income,
                demurrage)
end

function SuMSy(sumsy::SuMSy;
                seed::Real = sumsy.income.seed,
                guaranteed_income::Real = sumsy.income.guaranteed_income,
                dem_free::Real = sumsy.demurrage.dem_free,
                dem_settings::DemSettings = sumsy.demurrage.dem_tiers)
    return SuMSy(guaranteed_income, dem_free, dem_settings, seed = seed)
end

function make_tiers(dem_array::T) where T <: Vector{<: Vector{<: Real}}
    dem_settings = Vector{Tuple{Real, Real}}()

    for tier in dem_array
        push!(dem_settings, (tier[1], tier[2]))
    end

    return make_tiers(dem_settings)
end

"""
    make_tiers(dem_settings::Vector{T}) where  {T <: Tuple{Real, Real}}

Convert the vector of tuples into DemTiers.
The first interval always starts with 0, the last interval always has an unbounded upper bound. Tiers are sorted from low to high.
"""
function make_tiers(dem_settings::Vector{T}) where  {T <: Tuple{Real, Real}}
    sort!(dem_settings)
    tiers = DemTiers()
    lower_bound = 0
    demurrage = dem_settings[1][2]

    if length(dem_settings) > 1
        upper_bound = 0

        for index in 2:length(dem_settings)
            tuple = dem_settings[index]
            upper_bound = tuple[1]

            push!(tiers,
                (Interval{Currency, Open, Closed}(lower_bound, upper_bound),
                demurrage))

            lower_bound = upper_bound
            demurrage = tuple[2]
        end
    end

    push!(tiers,
        (Interval{Currency, Open, Unbounded}(lower_bound, nothing),
        demurrage))

    return tiers
end

make_tiers(demurrage_percentage::Real) = make_tiers([(0, demurrage_percentage)])

NO_DEM_TIERS = make_tiers([(0, 0)])
make_tiers(dem_tiers::DemTiers) = sort!(dem_tiers)

"""
    calculate_time_range_demurrage(balance::Real, dem_tiers::DemTiers, interval::Int, timerange::Int)
    * balance: The current balance.
    * dem_tiers: The demurrage tiers.
    * dem_free: The demurrage free amount.
    * interval: The demurrage interval.
    * timerange: The time range over which the demurrage is calculated.
    * allow_negative_demurrage: Whether or not negative demurrage is allowed.
Calculate the demurrage over a time range.
"""
function calculate_time_range_demurrage(balance::Real,
                                        dem_tiers::DemTiers,
                                        dem_free::Real,
                                        interval::Int,
                                        timerange::Int,
                                        allow_negative_demurrage::Bool)
    if balance > 0 || allow_negative_demurrage
        b_sign = sign(balance) # negative balances result in positive demurrage

        if balance > 0
            balance -= dem_free
        end

        balance *= b_sign

        demurrage = 0

        for tier in dem_tiers
            if balance <= 0
                break
            else
                if is_right_unbounded(tier[1])
                    amount = balance
                    balance = 0
                else
                    amount = min(span(tier[1]), balance)
                    balance -= amount
                end

                demurrage += amount * tier[2]
            end
        end

        demurrage *= timerange / interval * b_sign

        return Currency(demurrage)
    else
        return CUR_0
    end
end

function calculate_timerange_adjustments(balance::Real,
                                            sumsy::SuMSy,
                                            gi_eligible::Bool,
                                            dem_free::Real,
                                            interval::Int,
                                            timerange::Int,
                                            allow_negative_demurrage::Bool)
    guaranteed_income = gi_eligible ? sumsy.income.guaranteed_income * timerange / interval : CUR_0
    demurrage = calculate_time_range_demurrage(balance, sumsy.demurrage.dem_tiers, dem_free, interval, timerange, allow_negative_demurrage)

    return Currency(guaranteed_income), Currency(demurrage)
end

function calculate_timerange_adjustments(sumsy_balance::SuMSyBalance,
                                            timerange::Int,
                                            dep_entry::BalanceEntry = SUMSY_DEP)
    gi_eligible = is_gi_eligible(sumsy_balance, dep_entry)
    dem_free = get_dem_free(sumsy_balance, dep_entry)
    sumsy = get_sumsy(sumsy_balance, dep_entry)
    interval = get_sumsy_interval(sumsy_balance, dep_entry)
    guaranteed_income = CUR_0
    demurrage = CUR_0
    cur_balance = asset_value(sumsy_balance, dep_entry)

    if timerange >= interval
        for _ in 1:trunc(timerange/interval)
            g, d = calculate_timerange_adjustments(cur_balance,
                                                    sumsy,
                                                    gi_eligible,
                                                    dem_free,
                                                    interval,
                                                    interval,
                                                    allow_negative_demurrage(sumsy_balance, dep_entry))
            cur_balance += g - d
            guaranteed_income += g
            demurrage += d
        end

        timerange = mod(timerange, interval)
    end

    g, d = calculate_timerange_adjustments(cur_balance,
                                            sumsy,
                                            gi_eligible,
                                            dem_free,
                                            interval,
                                            timerange,
                                            allow_negative_demurrage(sumsy_balance, dep_entry))
    guaranteed_income += g
    demurrage += d

    return Currency(guaranteed_income), Currency(demurrage)
end

function telo(sumsy::SuMSy)
    return telo(sumsy.income.guaranteed_income, sumsy.demurrage.dem_tiers, sumsy.demurrage.dem_free)
end

function telo(income::Real, dem_settings::DemSettings, dem_free::Real = 0)
    return telo(Currency(income), make_tiers(dem_settings), Currency(dem_free))
end

function telo(income::Real, dem_tiers::DemTiers, dem_free::Real = 0)
    total_dem = 0
    telo_val = 0

    for tier in dem_tiers
        if is_right_unbounded(tier[1]) || total_dem + span(tier[1]) * tier[2] > income
            if tier[2] != 0
                telo_val += (income - total_dem) / tier[2]
            else
                telo_val = CUR_MAX
            end
            
            break
        else
            telo_val += span(tier[1])
            total_dem += span(tier[1]) * tier[2]
        end
    end

    return Currency(telo_val + dem_free)
end

function time_telo(sumsy::SuMSy, interval::Int, allow_negative_demurrage::Bool)
    t = 0
    eq = telo(sumsy) - sumsy.demurrage.dem_free
    balance = 0

    while balance < eq - 1
        guaranteed_income, demurrage = calculate_timerange_adjustments(balance,
                                                                        sumsy,
                                                                        true,
                                                                        sumsy.demurrage.dem_free,
                                                                        interval,
                                                                        interval,
                                                                        allow_negative_demurrage)
        balance += guaranteed_income - demurrage
        t += 1
    end

    return t
end

function calculate_sumsy_deposit(sumsy::SuMSy,
                                periods::Int,
                                start_amount::Real = CUR_0,
                                allow_negative_demurrage::Bool = false)
    amount = Currency(start_amount)

    for _ in 1:periods
        amount += Currency(sumsy.income.guaranteed_income - calculate_time_range_demurrage(amount,
                                                                                sumsy.demurrage.dem_tiers,
                                                                                sumsy.demurrage.dem_free,
                                                                                1,
                                                                                1,
                                                                                allow_negative_demurrage))
    end

    return amount
end
"""
    SuMSyAccrual

Bookkeeping that keeps the guaranteed income exact over a SuMSy period when settlements are more frequent than the period.

Guaranteed income and demurrage are defined per period (`sumsy_interval`). They are settled every `granularity` steps,
each settlement receiving `granularity / sumsy_interval` of the period's guaranteed income and demurrage rates.
The guaranteed income is rounded on its running total, so a full period always pays exactly the guaranteed income.

* gi_steps: the number of steps, since the start of the running period, for which guaranteed income was settled.
* gi_booked: the guaranteed income booked for those steps.
"""
mutable struct SuMSyAccrual{C <: FixedDecimal}
    gi_steps::Int
    gi_booked::C
end

SuMSyAccrual() = SuMSyAccrual{Currency}(0, CUR_0)

function check_granularity(granularity::Int)
    granularity >= 1 || throw(ArgumentError("granularity must be at least 1, got $granularity"))

    return granularity
end

Base.copy(a::SuMSyAccrual{C}) where {C} = SuMSyAccrual{C}(a.gi_steps, a.gi_booked)

"""
Demurrage tiers in a concrete form for fast settlement: (span, unbounded, rate).
"""
fast_tiers(dem_tiers::DemTiers, ::Type{C}) where {C} = [(is_right_unbounded(t[1]) ? zero(C) : C(span(t[1])),
                                                        is_right_unbounded(t[1]),
                                                        Float64(value(t[2]))) for t in dem_tiers]

"""
Same calculation as `calculate_time_range_demurrage`, with concrete types.
"""
function fast_time_range_demurrage(balance::C,
                                    tiers::Vector{Tuple{C, Bool, Float64}},
                                    dem_free::C,
                                    interval::Int,
                                    timerange::Int,
                                    allow_negative_demurrage::Bool) where {C <: FixedDecimal}
    if balance > 0 || allow_negative_demurrage
        b_sign = sign(balance)

        if balance > 0
            balance -= dem_free
        end

        balance *= b_sign
        demurrage = 0.0

        for (tier_span, unbounded, rate) in tiers
            if balance <= 0
                break
            elseif unbounded
                amount = balance
                balance = zero(C)
            else
                amount = min(tier_span, balance)
                balance -= amount
            end

            demurrage += amount * rate
        end

        demurrage *= timerange / interval * b_sign

        return C(demurrage)
    else
        return zero(C)
    end
end

"""
Settle `granules` granules. Function barrier: all arguments have concrete types.

# Returns
(guaranteed_income, demurrage, gi_steps, gi_booked)
"""
function settle_granules(base::C,
                        granules::Int,
                        granularity::Int,
                        interval::Int,
                        income::C,
                        gi_eligible::Bool,
                        tiers::Vector{Tuple{C, Bool, Float64}},
                        dem_free::C,
                        negative_demurrage::Bool,
                        gi_steps::Int,
                        gi_booked::C) where {C <: FixedDecimal}
    guaranteed_income = zero(C)
    demurrage = zero(C)

    for _ in 1:granules
        d = fast_time_range_demurrage(base, tiers, dem_free, interval, granularity, negative_demurrage)
        g = zero(C)

        if gi_eligible
            gi_steps += granularity
            due = C(income * gi_steps / interval)
            g = due - gi_booked
            gi_booked = due

            if gi_steps % interval == 0
                # Full periods paid exactly: restart the running total.
                gi_steps = 0
                gi_booked = zero(C)
            end
        end

        base += g - d
        guaranteed_income += g
        demurrage += d
    end

    return guaranteed_income, demurrage, gi_steps, gi_booked
end

"""
    accrue_sumsy(sumsy_balance::SuMSyBalance, dep_entry::BalanceEntry, timestamp::Int)

Calculate the guaranteed income and demurrage that must be booked to settle all complete granules up to `timestamp`.
Nothing is changed.

Every granule is settled on the balance at the end of the granule. Steps after the last complete granule carry over
to the next settlement. Because SuMSy bookings and transfers settle the elapsed granules first, the result does not
depend on how often the balance is adjusted.

# Returns
(guaranteed_income, demurrage, accrual, last_adjustment): the amounts to book, the accrual state and the
last adjustment timestamp after booking them.
"""
function accrue_sumsy(sumsy_balance::SuMSyBalance, dep_entry::BalanceEntry, timestamp::Int)
    accrual = get_accrual(sumsy_balance, dep_entry)
    last_adjustment = get_last_adjustment(sumsy_balance, dep_entry)

    if !is_sumsy_active(sumsy_balance, dep_entry)
        # Inactive balances do not accrue. Restart the granules when the balance is adjusted.
        return CUR_0, CUR_0, SuMSyAccrual(), max(timestamp, last_adjustment)
    end

    granularity = get_granularity(sumsy_balance, dep_entry)
    granules = max(0, (timestamp - last_adjustment) ÷ granularity)

    if granules == 0
        return CUR_0, CUR_0, copy(accrual), last_adjustment
    end

    base = asset_value(get_balance(sumsy_balance), dep_entry)
    C = typeof(base)
    guaranteed_income, demurrage, gi_steps, gi_booked = settle_granules(base,
                                                                        granules,
                                                                        granularity,
                                                                        get_sumsy_interval(sumsy_balance, dep_entry),
                                                                        C(get_guaranteed_income(sumsy_balance, dep_entry)),
                                                                        is_gi_eligible(sumsy_balance, dep_entry),
                                                                        fast_tiers(get_dem_tiers(sumsy_balance, dep_entry), C),
                                                                        C(get_dem_free(sumsy_balance, dep_entry)),
                                                                        allow_negative_demurrage(sumsy_balance, dep_entry),
                                                                        accrual.gi_steps,
                                                                        C(accrual.gi_booked))

    return guaranteed_income, demurrage, SuMSyAccrual{C}(gi_steps, gi_booked), last_adjustment + granules * granularity
end
