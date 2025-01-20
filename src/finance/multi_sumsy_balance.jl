import Base: ==

mutable struct MultiSuMSyBalance{C <: FixedDecimal} <: SuMSyBalance{C}
    balance::Balance
    sumsy::Dict{BalanceEntry, SuMSy}
    sumsy_active::Dict{BalanceEntry, Bool}
    gi_eligible::Dict{BalanceEntry, Bool}
    last_adjustment::Dict{BalanceEntry, Integer}
    dem_free::Dict{BalanceEntry, C}
    sumsy_interval::Dict{BalanceEntry, Int}
    transactional::Dict{BalanceEntry, Bool}
    allow_negative_sumsy::Dict{BalanceEntry, Bool}
    allow_negative_demurrage::Dict{BalanceEntry, Bool}
    MultiSuMSyBalance(balance::Balance = Balance()) = new{Currency}(balance,
                                                            Dict{BalanceEntry, SuMSy}(),
                                                            Dict{BalanceEntry, Bool}(),
                                                            Dict{BalanceEntry, Bool}(),
                                                            Dict{BalanceEntry, Integer}(),
                                                            Dict{BalanceEntry, Currency}(),
                                                            Dict{BalanceEntry, Int}(),
                                                            Dict{BalanceEntry, Bool}(),
                                                            Dict{BalanceEntry, Bool}(),
                                                            Dict{BalanceEntry, Bool}())
end

struct SuMSyConfig
    sumsy::SuMSy
    dep_entry::BalanceEntry
    gi_eligible::Bool
    activate::Bool
    initialize::Bool
    sumsy_interval::Int
    transactional::Bool
    allow_negative_sumsy::Bool
    allow_negative_demurrage::Bool
    SuMSyConfig(sumsy::SuMSy,
                dep_entry::BalanceEntry;
                gi_eligible::Bool = true,
                activate::Bool = true,
                initialize::Bool = true,
                sumsy_interval::Int = 30,
                transactional::Bool = false,
                allow_negative_sumsy::Bool = false,
                allow_negative_demurrage::Bool = false) = new(sumsy,
                                                    dep_entry,
                                                    gi_eligible,
                                                    activate,
                                                    initialize,
                                                    sumsy_interval,
                                                    transactional,
                                                    allow_negative_sumsy,
                                                    allow_negative_demurrage)
end

function MultiSuMSyBalance(sumsy::SuMSy,
                            dep_entry::BalanceEntry,
                            balance::Balance = Balance();
                            activate = true,
                            gi_eligible::Bool = true,
                            initialize = true,
                            sumsy_interval::Int = 30,
                            transactional::Bool = false,
                            allow_negative_assets::Bool = true,
                            allow_negative_liabilities::Bool = true,
                            allow_negative_sumsy::Bool = false,
                            allow_negative_demurrage::Bool = false)
    def_min_asset!(balance, allow_negative_assets ? typemin(Currency) : CUR_0)
    def_min_liability!(balance, allow_negative_liabilities ? typemin(Currency) : CUR_0)

    sumsy_balance = MultiSuMSyBalance(balance)

    set_sumsy!(sumsy_balance,
                sumsy,
                dep_entry,
                gi_eligible = gi_eligible,
                activate = activate,
                reset_balance = initialize,
                sumsy_interval = sumsy_interval,
                transactional = transactional,
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

get_sumsy_interval(sumsy_balance::MultiSuMSyBalance, entry::BalanceEntry) = sumsy_balance.sumsy_interval[entry]
is_transactional(sumsy_balance::MultiSuMSyBalance, entry::BalanceEntry) = sumsy_balance.transactional[entry]
allow_negative_demurrage(sumsy_balance::MultiSuMSyBalance, dep_entry::BalanceEntry = SUMSY_DEP) = sumsy_balance.allow_negative_demurrage[dep_entry]

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
                        dep_entry::BalanceEntry;
                        timestamp::Int = get_last_adjustment(sumsy_balance, dep_entry))
    value = asset_value(get_balance(sumsy_balance), dep_entry)
    guaranteed_income, demurrage = calculate_adjustments(sumsy_balance, dep_entry, timestamp)

    return value + guaranteed_income - demurrage
end

"""
    adjust_sumsy_balance!(sumsy_balance::SuMSyBalance,
                        sumsy_params::SuMSyParams,
                        timestamp::Int)
"""
function adjust_sumsy_balance!(sumsy_balance::MultiSuMSyBalance, dep_entry::BalanceEntry, timestamp::Int)
    guaranteed_income, demurrage = calculate_adjustments(sumsy_balance, dep_entry, timestamp)

    book_asset!(get_balance(sumsy_balance), dep_entry, guaranteed_income - demurrage, timestamp = timestamp)
    set_last_adjustment!(sumsy_balance, dep_entry, timestamp)

    return guaranteed_income, demurrage
end

function calculate_adjustments(sumsy_balance::MultiSuMSyBalance,
                                dep_entry::BalanceEntry,
                                timestamp::Int,
                                sumsy::SuMSy = get_sumsy(sumsy_balance, dep_entry))
    sumsy_interval = get_sumsy_interval(sumsy_balance, dep_entry)
    timerange = 0

    if is_sumsy_active(sumsy_balance, dep_entry)
        if is_transactional(sumsy_balance, dep_entry)
            timerange = max(0, timestamp - get_last_adjustment(sumsy_balance, dep_entry))
        else         
            timerange = max(0, trunc((timestamp - get_last_adjustment(sumsy_balance, dep_entry)) / sumsy_interval) * sumsy_interval)
        end
    end

    return timerange > 0 ? calculate_timerange_adjustments(sumsy_balance,
                                                            dep_entry,
                                                            is_gi_eligible(sumsy_balance, dep_entry),
                                                            get_dem_free(sumsy_balance, dep_entry),
                                                            Int(timerange)) : (CUR_0, CUR_0)
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
            book_asset!(balance, dep_entry, get_guaranteed_income(sumsy_balance, dep_entry), timestamp = timestamp)
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

    if is_transactional(sumsy_balance, dep_entry)
        set_last_adjustment!(sumsy_balance, dep_entry, timestamp)
    end
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
                    transactional::Bool = is_transactional(sumsy_balance, dep_entry),
                    allow_negative_sumsy::Bool = false,
                    allow_negative_demurrage::Bool = false)
    sumsy_balance.sumsy[dep_entry] = sumsy
    sumsy_balance.gi_eligible[dep_entry] = gi_eligible
    sumsy_balance.sumsy_active[dep_entry] = activate
    sumsy_balance.sumsy_interval[dep_entry] = sumsy_interval
    sumsy_balance.transactional[dep_entry] = transactional
    sumsy_balance.allow_negative_demurrage[dep_entry] = allow_negative_demurrage

    if allow_negative_sumsy
        typemin_asset!(get_balance(sumsy_balance), dep_entry)
    else
        min_asset!(get_balance(sumsy_balance), dep_entry, CUR_0)
    end

    # Do not change last adjustment if it already exists
    if !haskey(sumsy_balance.last_adjustment, dep_entry)
        sumsy_balance.last_adjustment[dep_entry] = timestamp
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
                umsy_config.dep_entry,
                gi_eligible = sumsy_config.gi_eligible,
                activate = sumsy_config.activate,
                reset_balance = sumsy_config.initialize,
                sumsy_interval = sumsy_config.sumsy_interval,
                transactional = sumsy_config.transactional,
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

function set_last_adjustment!(sumsy_balance::MultiSuMSyBalance, dep_entry::BalanceEntry, timestamp::Int)
    sumsy_balance.last_adjustment[dep_entry] = timestamp

    return timestamp
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
If SuMSy is transactional and active for the balance, partial guaranteed income and demurrage are calculated and applied first,
and the timestamp is stored on the balance.
"""
function book_sumsy!(sumsy_balance::MultiSuMSyBalance,
                        dep_entry::BalanceEntry,
                        amount::Real;
                        timestamp::Int = get_last_adjustment(sumsy_balance, dep_entry),
                        set_to_value::Bool = false)
    if !set_to_value && is_transactional(sumsy_balance, dep_entry)
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
    if is_transactional(source, dep_entry)
        adjust_sumsy_balance!(source, dep_entry, timestamp)
    end

    if is_transactional(destination, dep_entry)
        adjust_sumsy_balance!(destination, dep_entry, timestamp)
    end

    transfer_asset!(get_balance(source),
                    get_balance(destination),
                    dep_entry,
                    amount,
                    timestamp = max(timestamp, max(get_last_transaction(source), get_last_transaction(destination))))
end

"""
    transfer_dem_free!(source::Balance, destination::Balance, amount::Real)

Transfer a part or all of the demurrage free buffer from one balance to another. No more than the available demurrage free buffer can be transferred.
If the SuMSy implementation is transaction based, partial guaranteed income and demurrage will be calculated and applied first.
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
    if is_transactional(source, dep_entry)
        adjust_balance(source, dep_entry, timestamp)
    end

    if is_transactional(destination, dep_entry)
        adjust_balance(destination, dep_entry, timestamp)
    end

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
