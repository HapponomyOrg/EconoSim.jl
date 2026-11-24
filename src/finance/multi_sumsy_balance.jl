import Base: ==

mutable struct MultiSuMSyBalance{C <: FixedDecimal} <: SuMSyBalance{C}
    balance::Balance
    def_sumsy_entry::BalanceEntry
    sumsy::Dict{BalanceEntry, SuMSy}
    sumsy_active::Dict{BalanceEntry, Bool}
    gi_eligible::Dict{BalanceEntry, Bool}
    last_adjustment::Dict{BalanceEntry, Integer}
    dem_free::Dict{BalanceEntry, C}
    sumsy_interval::Dict{BalanceEntry, Int}
    granularity::Dict{BalanceEntry, Int}
    allow_negative_sumsy::Dict{BalanceEntry, Bool}
    allow_negative_demurrage::Dict{BalanceEntry, Bool}
    accrual::Dict{BalanceEntry, SuMSyAccrual{C}}
    MultiSuMSyBalance(balance::Balance = Balance(),
                        def_sumsy_entry::BalanceEntry = SUMSY_DEP) = new{Currency}(balance,
                                                                                    def_sumsy_entry,
                                                                                    Dict{BalanceEntry, SuMSy}(),
                                                                                    Dict{BalanceEntry, Bool}(),
                                                                                    Dict{BalanceEntry, Bool}(),
                                                                                    Dict{BalanceEntry, Integer}(),
                                                                                    Dict{BalanceEntry, Currency}(),
                                                                                    Dict{BalanceEntry, Int}(),
                                                                                    Dict{BalanceEntry, Int}(),
                                                                                    Dict{BalanceEntry, Bool}(),
                                                                                    Dict{BalanceEntry, Bool}(),
                                                                                    Dict{BalanceEntry, SuMSyAccrual{Currency}}())
end

struct SuMSyConfig
    sumsy::SuMSy
    dep_entry::BalanceEntry
    gi_eligible::Bool
    activate::Bool
    initialize::Bool
    sumsy_interval::Int
    granularity::Int
    allow_negative_sumsy::Bool
    allow_negative_demurrage::Bool
    SuMSyConfig(sumsy::SuMSy,
                dep_entry::BalanceEntry;
                gi_eligible::Bool = true,
                activate::Bool = true,
                initialize::Bool = true,
                sumsy_interval::Int = 30,
                granularity::Int = sumsy_interval,
                allow_negative_sumsy::Bool = false,
                allow_negative_demurrage::Bool = false) = new(sumsy,
                                                    dep_entry,
                                                    gi_eligible,
                                                    activate,
                                                    initialize,
                                                    sumsy_interval,
                                                    check_granularity(granularity, sumsy_interval),
                                                    allow_negative_sumsy,
                                                    allow_negative_demurrage)
end

function MultiSuMSyBalance(sumsy::SuMSy,
                            def_sumsy_entry::BalanceEntry = SUMSY_DEP,
                            balance::Balance = Balance();
                            activate = true,
                            gi_eligible::Bool = true,
                            initialize = true,
                            sumsy_interval::Int = 30,
                            granularity::Int = sumsy_interval,
                            allow_negative_assets::Bool = true,
                            allow_negative_liabilities::Bool = true,
                            allow_negative_sumsy::Bool = false,
                            allow_negative_demurrage::Bool = false)
    check_granularity(granularity, sumsy_interval)
    def_min_asset!(balance, allow_negative_assets ? typemin(Currency) : CUR_0)
    def_min_liability!(balance, allow_negative_liabilities ? typemin(Currency) : CUR_0)

    sumsy_balance = MultiSuMSyBalance(balance, def_sumsy_entry)

    set_sumsy!(sumsy_balance,
                sumsy,
                def_sumsy_entry,
                gi_eligible = gi_eligible,
                activate = activate,
                reset_balance = initialize,
                sumsy_interval = sumsy_interval,
                granularity = granularity,
                allow_negative_sumsy = allow_negative_sumsy,
                allow_negative_demurrage = allow_negative_demurrage)
    
    return sumsy_balance
end

function MultiSuMSyBalance(sumsy_config::SuMSyConfig,
                            balance::Balance = Balance())
    sumsy_balance = MultiSuMSyBalance(balance)
    set_sumsy!(sumsy_balance, sumsy_config)
    
    return sumsy_balance
end

function MultiSuMSyBalance(sumsy_configs::Union{AbstractVector{SuMSyConfig}, AbstractSet{SuMSyConfig}},
                            balance::Balance = Balance())
    sumsy_balance = MultiSuMSyBalance(balance)

    for sumsy_config in sumsy_configs
        set_sumsy!(sumsy_balance, sumsy_config)
    end
    
    return sumsy_balance
end

function Base.getproperty(sumsy_balance::MultiSuMSyBalance, s::Symbol)
    if s in fieldnames(MultiSuMSyBalance)
        return getfield(sumsy_balance, s)
    else
        return getproperty(getfield(sumsy_balance, :balance), s)
    end
end

function Base.setproperty!(sumsy_balance::MultiSuMSyBalance, s::Symbol, value)
    if s in fieldnames(MultiSuMSyBalance)
        setfield!(sumsy_balance, s, value)
    else
        setproperty!(getfield(sumsy_balance, :balance), s, value)
    end

    return value
end

function Base.hasproperty(sumsy_balance::MultiSuMSyBalance, s::Symbol)
    return s in fieldnames(MultiSuMSyBalance) || hasproperty(getfield(sumsy_balance, :balance), s)
end

get_balance(sumsy_balance::MultiSuMSyBalance) = sumsy_balance.balance

is_sumsy(sumsy_balance::MultiSuMSyBalance, entry::BalanceEntry) = entry in keys(sumsy_balance.sumsy)

get_def_sumsy_entry(sumsy_balance::MultiSuMSyBalance) = sumsy_balance.def_sumsy_entry
get_sumsy_interval(sumsy_balance::MultiSuMSyBalance, entry::BalanceEntry) = sumsy_balance.sumsy_interval[entry]
get_granularity(sumsy_balance::MultiSuMSyBalance, entry::BalanceEntry) = get(sumsy_balance.granularity, entry) do
    get_sumsy_interval(sumsy_balance, entry)
end

"""
    set_granularity!(sumsy_balance::MultiSuMSyBalance, granularity::Int, entry::BalanceEntry)

Change the number of steps between settlements. Settle the entry first (`adjust_sumsy_balance!`), otherwise the
granules that have elapsed are settled with the new granularity.
"""
set_granularity!(sumsy_balance::MultiSuMSyBalance, granularity::Int, entry::BalanceEntry) = (sumsy_balance.granularity[entry] = check_granularity(granularity, get_sumsy_interval(sumsy_balance, entry)))
allow_negative_demurrage(sumsy_balance::MultiSuMSyBalance, entry::BalanceEntry = SUMSY_DEP) = sumsy_balance.allow_negative_demurrage[entry]

function book_asset!(sumsy_balance::MultiSuMSyBalance,
                        entry::BalanceEntry,
                        amount::Real;
                        set_to_value::Bool = false,
                        timestamp::Int = get_last_transaction(sumsy_balance))
    if is_sumsy(sumsy_balance, entry)
        book_sumsy!(sumsy_balance, entry, amount, timestamp = timestamp, set_to_value = set_to_value)
    else
        book_asset!(get_balance(sumsy_balance), entry, amount, set_to_value = set_to_value, timestamp = timestamp)
    end
end

function transfer!(sumsy_balance1::AbstractBalance,
                    type1::EntryType,
                    entry1::BalanceEntry,
                    sumsy_balance2::MultiSuMSyBalance,
                    type2::EntryType,
                    entry2::BalanceEntry,
                    amount::Real;
                    timestamp::Int = max(get_last_transaction(sumsy_balance1), get_last_transaction(sumsy_balance2)))
    if type1 === type2 === asset && entry1 === entry2 && is_sumsy(sumsy_balance1, entry1) && is_sumsy(sumsy_balance2, entry2)
        return false # SuMSy money can not be transferred to a non SuMSy balance
    else
        transfer!(get_balance(sumsy_balance1),
                    type1,
                    entry1,
                    get_balance(sumsy_balance2),
                    type2,
                    entry2,
                    amount,
                    timestamp = timestamp)
    end
end

function transfer!(sumsy_balance1::MultiSuMSyBalance,
                    type1::EntryType,
                    entry1::BalanceEntry,
                    sumsy_balance2::MultiSuMSyBalance,
                    type2::EntryType,
                    entry2::BalanceEntry,
                    amount::Real;
                    timestamp::Int = max(get_last_transaction(sumsy_balance1), get_last_transaction(sumsy_balance2)))
    if type1 === type2 === asset && entry1 === entry2 && is_sumsy(sumsy_balance1, entry1) && is_sumsy(sumsy_balance2, entry2)
        transfer_sumsy!(source, destination, entry1, amount, timestamp = timestamp)
    else
        transfer!(get_balance(sumsy_balance1),
                    type1,
                    entry1,
                    get_balance(sumsy_balance2),
                    type2,
                    entry2,
                    amount,
                    timestamp = timestamp)
    end
end

function transfer!(sumsy_balance1::MultiSuMSyBalance,
                type1::EntryType,
                sumsy_balance2::MultiSuMSyBalance,
                type2::EntryType,
                entry::BalanceEntry,
                amount::Real;
                timestamp::Int = max(get_last_transaction(sumsy_balance1), get_last_transaction(sumsy_balance2)))
    transfer!(sumsy_balance1, type1, entry, sumsy_balance2, type2, entry, amount, timestamp = timestamp)
end

function transfer_asset!(sumsy_balance1::MultiSuMSyBalance,
                sumsy_balance2::MultiSuMSyBalance,
                entry::BalanceEntry,
                amount::Real;
                timestamp::Int = max(get_last_transaction(sumsy_balance1), get_last_transaction(sumsy_balance2)))
    transfer!(sumsy_balance1, asset, entry, sumsy_balance2, asset, entry, amount, timestamp = timestamp)
end

function transfer_asset!(sumsy_balance1::MultiSuMSyBalance,
                entry1::BalanceEntry,
                sumsy_balance2::MultiSuMSyBalance,
                entry2::BalanceEntry,
                amount::Real;
                timestamp::Int = max(get_last_transaction(sumsy_balance1), get_last_transaction(sumsy_balance2)))
    transfer!(sumsy_balance1, asset, entry1, sumsy_balance2, asset, entry2, amount, timestamp = timestamp)
end

function asset_value(sumsy_balance::MultiSuMSyBalance, entry::BalanceEntry)
    if is_sumsy(sumsy_balance, entry)
        return sumsy_assets(sumsy_balance, entry)
    else
        return asset_value(get_balance(sumsy_balance), entry)
    end
end

function sumsy_assets(sumsy_balance::MultiSuMSyBalance,
                        dep_entry::BalanceEntry = sumsy_balance.def_sumsy_entry;
                        timestamp::Int = get_last_adjustment(sumsy_balance, dep_entry))
    value = asset_value(get_balance(sumsy_balance), dep_entry)
    guaranteed_income, demurrage = calculate_adjustments(sumsy_balance, dep_entry, timestamp)

    return value + guaranteed_income - demurrage
end

"""
    adjust_sumsy_balance!(sumsy_balance::MultiSuMSyBalance, dep_entry::BalanceEntry, timestamp::Int)

Settle all complete granules of `dep_entry` up to `timestamp`. See `book_settlement!`.

# Returns
(guaranteed_income, demurrage)
"""
function adjust_sumsy_balance!(sumsy_balance::MultiSuMSyBalance, dep_entry::BalanceEntry, timestamp::Int)
    guaranteed_income, demurrage, accrual, last_adjustment = accrue_sumsy(sumsy_balance, dep_entry, timestamp)

    book_settlement!(sumsy_balance, dep_entry, guaranteed_income - demurrage, timestamp)
    sumsy_balance.accrual[dep_entry] = accrual
    sumsy_balance.last_adjustment[dep_entry] = last_adjustment

    return guaranteed_income, demurrage
end

function calculate_adjustments(sumsy_balance::MultiSuMSyBalance,
                                dep_entry::BalanceEntry,
                                timestamp::Int)
    if !haskey(sumsy_balance.sumsy, dep_entry)
        return CUR_0, CUR_0
    end

    guaranteed_income, demurrage, _, _ = accrue_sumsy(sumsy_balance, dep_entry, timestamp)

    return guaranteed_income, demurrage
end

function reset_sumsy_balance!(sumsy_balance::MultiSuMSyBalance,
                                dep_entry::BalanceEntry;
                                reset_balance::Bool = true,
                                reset_dem_free::Bool = true,
                                timestamp::Int = get_last_adjustment(sumsy_balance, dep_entry))
    balance = get_balance(sumsy_balance)

    if reset_balance
        if is_gi_eligible(sumsy_balance, dep_entry)
            book_asset!(balance, dep_entry, get_seed(sumsy_balance, dep_entry), set_to_value = true, timestamp = timestamp)
        else
            book_asset!(balance, dep_entry, 0, set_to_value = true, timestamp = timestamp)
        end
    end

    if reset_dem_free
        if is_gi_eligible(sumsy_balance, dep_entry)
            set_dem_free!(sumsy_balance, dep_entry, get_initial_dem_free(sumsy_balance, dep_entry))
        else
            set_dem_free!(sumsy_balance, dep_entry, 0)
        end
    end

    # Start settling from the reset timestamp.
    set_last_adjustment!(sumsy_balance, dep_entry, timestamp)
end

function set_sumsy!(sumsy_balance::MultiSuMSyBalance,
                    sumsy::SuMSy,
                    dep_entry::BalanceEntry;
                    gi_eligible::Bool = true,
                    activate::Bool = true,
                    reset_balance::Bool = true,
                    reset_dem_free::Bool = true,
                    timestamp::Int = get_last_adjustment(sumsy_balance, dep_entry),
                    sumsy_interval::Int = get_sumsy_interval(sumsy_balance, dep_entry),
                    granularity::Int = haskey(sumsy_balance.granularity, dep_entry) ? sumsy_balance.granularity[dep_entry] : sumsy_interval,
                    allow_negative_sumsy::Bool = false,
                    allow_negative_demurrage::Bool = false)
    check_granularity(granularity, sumsy_interval)
    sumsy_balance.sumsy[dep_entry] = sumsy
    sumsy_balance.gi_eligible[dep_entry] = gi_eligible
    sumsy_balance.sumsy_active[dep_entry] = activate
    sumsy_balance.sumsy_interval[dep_entry] = sumsy_interval
    sumsy_balance.granularity[dep_entry] = granularity
    sumsy_balance.allow_negative_demurrage[dep_entry] = allow_negative_demurrage

    if allow_negative_sumsy
        typemin_asset!(get_balance(sumsy_balance), dep_entry)
    else
        min_asset!(get_balance(sumsy_balance), dep_entry, CUR_0)
    end

    # Do not change last adjustment if it already exists
    if !haskey(sumsy_balance.last_adjustment, dep_entry)
        set_last_adjustment!(sumsy_balance, dep_entry, timestamp)
    end
    
    reset_sumsy_balance!(sumsy_balance,
                            dep_entry,
                            reset_balance = reset_balance,
                            reset_dem_free = reset_dem_free,
                            timestamp = timestamp)
end

function set_sumsy!(sumsy_balance::MultiSuMSyBalance, sumsy_config::SuMSyConfig)
    set_sumsy!(sumsy_balance,
                sumsy_config.sumsy,
                sumsy_config.dep_entry,
                gi_eligible = sumsy_config.gi_eligible,
                activate = sumsy_config.activate,
                reset_balance = sumsy_config.initialize,
                sumsy_interval = sumsy_config.sumsy_interval,
                granularity = sumsy_config.granularity,
                allow_negative_sumsy = sumsy_config.allow_negative_sumsy,
                allow_negative_demurrage = sumsy_config.allow_negative_demurrage)
end

function get_sumsy(sumsy_balance::MultiSuMSyBalance, dep_entry::BalanceEntry)
    try
        return sumsy_balance.sumsy[dep_entry]
    catch
        return nothing
    end
end

"""
    set_sumsy_active!(balance::Balance, sumsy::SuMSy, flag::Bool)

Indicate whether the balance participates in the specified SuMSy or not.
"""
function set_sumsy_active!(sumsy_balance::MultiSuMSyBalance, dep_entry::BalanceEntry, flag::Bool)
    sumsy_balance.sumsy_active[dep_entry] = flag
end

"""
    set_sumsy_active!(balance::Balance, sumsy::SuMSy, flag::Bool)

Set all SuMSy entries to the specified value.
"""
function set_sumsy_active!(sumsy_balance::MultiSuMSyBalance, flag::Bool)
    for dep_entry in keys(sumsy_balance.sumsy_active)
        sumsy_balance.sumsy_active[dep_entry] = flag
    end
end

function is_sumsy_active(sumsy_balance::MultiSuMSyBalance, dep_entry::BalanceEntry)
    try
        return sumsy_balance.sumsy_active[dep_entry]
    catch
        return false
    end
end

"""
    is_sumsy_active(balance::Balance)

Check whether all SuMSy entries are active.
"""
function is_sumsy_active(sumsy_balance::MultiSuMSyBalance)
    for dep_entry in keys(sumsy_balance.sumsy_active)
        if !sumsy_balance.sumsy_active[dep_entry]
            return false
        end
    end

    return true
end

function set_gi_eligible!(sumsy_balance::MultiSuMSyBalance, dep_entry::BalanceEntry, flag::Bool)
    sumsy_balance.gi_eligible[dep_entry] = flag
end

function is_gi_eligible(sumsy_balance::MultiSuMSyBalance, dep_entry::BalanceEntry)
    try
        return sumsy_balance.gi_eligible[dep_entry]
    catch
        return false
    end
end

function get_seed(sumsy_balance::MultiSuMSyBalance, dep_entry::BalanceEntry)
    try
        return get_sumsy(sumsy_balance, dep_entry).income.seed
    catch
        return CUR_0
    end
end

function get_guaranteed_income(sumsy_balance::MultiSuMSyBalance, dep_entry::BalanceEntry)
    try
        return get_sumsy(sumsy_balance, dep_entry).income.guaranteed_income
    catch
        return CUR_0
    end
end

function get_dem_tiers(sumsy_balance::MultiSuMSyBalance, dep_entry::BalanceEntry)
    try
        return get_sumsy(sumsy_balance, dep_entry).demurrage.dem_tiers
    catch
        return 0
    end
end

"""
    get_initial_dem_free(balance::Balance, sumsy::SuMSy)

Returns the initial size of the demurrage free buffer.
"""
function get_initial_dem_free(sumsy_balance::MultiSuMSyBalance, dep_entry::BalanceEntry)
    try
        return get_sumsy(sumsy_balance, dep_entry).demurrage.dem_free
    catch
        return CUR_0
    end
end

function set_dem_free!(sumsy_balance::MultiSuMSyBalance, dep_entry::BalanceEntry, amount::Real)
    try
        sumsy_balance.dem_free[dep_entry] = amount
        return amount
    catch
        return CUR_0
    end
end

function get_dem_free(sumsy_balance::MultiSuMSyBalance, dep_entry::BalanceEntry)
    try
        if is_gi_eligible(sumsy_balance, dep_entry)
            return sumsy_balance.dem_free[dep_entry]
        else
            return CUR_0
        end
    catch
        return CUR_0
    end
end

"""
    set_last_adjustment!(sumsy_balance::MultiSuMSyBalance, dep_entry::BalanceEntry, timestamp::Int)

Set the last adjustment timestamp of a SuMSy entry. A new SuMSy period starts at that timestamp.
"""
function set_last_adjustment!(sumsy_balance::MultiSuMSyBalance, dep_entry::BalanceEntry, timestamp::Int)
    sumsy_balance.accrual[dep_entry] = SuMSyAccrual()
    sumsy_balance.last_adjustment[dep_entry] = timestamp

    return timestamp
end

get_accrual(sumsy_balance::MultiSuMSyBalance, dep_entry::BalanceEntry) = get(sumsy_balance.accrual, dep_entry) do
    SuMSyAccrual()
end

function get_last_adjustment(sumsy_balance::MultiSuMSyBalance, dep_entry::BalanceEntry)
    try
        return sumsy_balance.last_adjustment[dep_entry]
    catch
        return 0
    end
end

"""
    book_sumsy!(balance::Balance, sumsy::SuMSy, amount::Real, timestamp = 0)

Books an amount on the asset side of the balance, under the SuMSy deposit entry.
The granules that have elapsed up to the timestamp are settled first, so the booking only affects later granules.
"""
function book_sumsy!(sumsy_balance::MultiSuMSyBalance,
                        dep_entry::BalanceEntry,
                        amount::Real;
                        timestamp::Int = get_last_adjustment(sumsy_balance, dep_entry),
                        set_to_value::Bool = false)
    if !set_to_value
        adjust_sumsy_balance!(sumsy_balance, dep_entry, timestamp)
    end

    book_asset!(get_balance(sumsy_balance),
                dep_entry, amount,
                set_to_value = set_to_value,
                timestamp = max(timestamp, get_last_transaction(sumsy_balance)))
end

"""
    transfer_sumsy!(source::SingleSuMSyBalance,
                    destination::SingleSuMSyBalance,
                    amount::Real,
                    timestamp::Int = 0)

Transfer an amount of SuMSy money from one balance sheet to another. No more than the available amount of money can be transferred.
Negative amounts result in a transfer from destination to source.
"""
function transfer_sumsy!(source::MultiSuMSyBalance,
                            destination::MultiSuMSyBalance,
                            dep_entry::BalanceEntry,
                            amount::Real;
                            timestamp::Int = max(get_last_adjustment(source, dep_entry), get_last_adjustment(destination, dep_entry)))
    # Settle the elapsed granules first.
    adjust_sumsy_balance!(source, dep_entry, timestamp)
    adjust_sumsy_balance!(destination, dep_entry, timestamp)

    transfer_asset!(get_balance(source),
                    get_balance(destination),
                    dep_entry,
                    amount,
                    timestamp = max(timestamp, max(get_last_transaction(source), get_last_transaction(destination))))
end

"""
    transfer_dem_free!(source::Balance, destination::Balance, amount::Real)

Transfer a part or all of the demurrage free buffer from one balance to another. No more than the available demurrage free buffer can be transferred.
The granules that have elapsed up to the timestamp are settled first.
* source::Balance - the balance from which the demurrage free amount is taken.
* destination::Balance - the balance to which the demurrage free buffer is transferred.
* amount::Real - the amount to be transferred.
* return - whether or not the transaction was succesful.
"""
function transfer_dem_free!(source::MultiSuMSyBalance,
                            destination::MultiSuMSyBalance,
                            dep_entry::BalanceEntry,
                            amount::Real;
                            timestamp::Int = max(get_last_adjustment(source, dep_entry), get_last_adjustment(destination, dep_entry)))
    # Settle the elapsed granules first.
    adjust_sumsy_balance!(source, dep_entry, timestamp)
    adjust_sumsy_balance!(destination, dep_entry, timestamp)

    available_dem_free = get_dem_free(source, dep_entry)
    amount = min(amount, available_dem_free)
    set_dem_free!(source, dep_entry, available_dem_free - amount)
    set_dem_free!(destination, dep_entry, get_dem_free(destination, dep_entry) + amount)

    return amount
end

function sumsy_loan!(creditor::MultiSuMSyBalance,
            debtor::MultiSuMSyBalance,
            amount::Real,
            installments::Integer,
            interval::Int = 1,
            timestamp::Int = 0;
            interest_rate::Real = 0,
            money_entry::BalanceEntry,
            debt_entry::BalanceEntry)
    return borrow(get_balance(creditor),
                    get_balance(debtor),
                    amount,
                    interest_rate,
                    installments,
                    interval,
                    timestamp,
                    bank_loan = false,
                    negative_allowed = false,
                    money_entry = money_entry,
                    debt_entry = debt_entry)
end
