
"""
    A SuMSy balance which only has one SuMSy balance sheet entry.
    Once initialized, all future SuMSy operations on the balance are assumed to refer to the initial balance sheet entry.
"""
mutable struct SingleSuMSyBalance <: SuMSyBalance
    balance::Balance
    sumsy::SuMSy
    sumsy_active::Bool
    gi_eligible::Bool
    dem_free::Currency
    last_adjustment::Int64
end

function SingleSuMSyBalance(sumsy::SuMSy,
                            balance::Balance = Balance();
                            activate::Bool = true,
                            gi_eligible::Bool = true,
                            initialize::Bool = true,
                            last_adjustment::Int = 0)
    sumsy_balance = SingleSuMSyBalance(balance, sumsy, activate, gi_eligible, sumsy.demurrage.dem_free, last_adjustment)
    
    if initialize
        reset_sumsy_balance!(sumsy_balance, reset_balance = initialize)
    end

    return sumsy_balance
end

function Base.getproperty(sumsy_balance::SingleSuMSyBalance, s::Symbol)
    if s in fieldnames(SingleSuMSyBalance)
        return getfield(sumsy_balance, s)
    else
        return getproperty(getfield(sumsy_balance, :balance), s)
    end
end

function Base.setproperty!(sumsy_balance::SingleSuMSyBalance, s::Symbol, value)
    if s in fieldnames(SingleSuMSyBalance)
        setfield!(sumsy_balance, s, value)
    else
        setproperty!(getfield(sumsy_balance, :balance), s, value)
    end

    return value
end

function Base.hasproperty(sumsy_balance::SingleSuMSyBalance, s::Symbol)
    return s in fieldnames(SingleSuMSyBalance) || hasproperty(getfield(sumsy_balance, :balance), s)
end

get_balance(sumsy_balance::SingleSuMSyBalance) = sumsy_balance.balance
get_sumsy_dep_entry(sumsy_balance::SingleSuMSyBalance) = SUMSY_DEP

set_last_adjustment!(sumsy_balance::SingleSuMSyBalance, timestamp::Int) = (sumsy_balance.last_adjustment = timestamp)
get_last_adjustment(sumsy_balance::SingleSuMSyBalance) = sumsy_balance.last_adjustment

function book_asset!(sumsy_balance::SingleSuMSyBalance,
                        entry::BalanceEntry,
                        amount::Real;
                        set_to_value::Bool = false,
                        timestamp::Int = get_last_transaction(sumsy_balance))
    if entry === SUMSY_DEP
        book_sumsy!(sumsy_balance, amount, timestamp, set_to_value = set_to_value)
    else
        book_asset!(get_balance(sumsy_balance), entry, amount, set_to_value = set_to_value, timestamp = timestamp)
    end
end

function transfer!(sumsy_balance1::AbstractBalance,
                    type1::EntryType,
                    entry1::BalanceEntry,
                    sumsy_balance2::SingleSuMSyBalance,
                    type2::EntryType,
                    entry2::BalanceEntry,
                    amount::Real;
                    timestamp::Int = max(get_last_transaction(sumsy_balance1), get_last_transaction(sumsy_balance2)))
    if entry1 === entry2 === SUMSY_DEP && type1 === type2 === asset
        return # SuMSy money can not be transferred to a non SuMSy balance
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

function transfer!(sumsy_balance1::SingleSuMSyBalance,
                    type1::EntryType,
                    entry1::BalanceEntry,
                    sumsy_balance2::AbstractBalance,
                    type2::EntryType,
                    entry2::BalanceEntry,
                    amount::Real;
                    timestamp::Int = max(get_last_transaction(sumsy_balance1), get_last_transaction(sumsy_balance2)))
    if entry1 === entry2 === SUMSY_DEP && type1 === type2 === asset
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

function transfer!(sumsy_balance1::SingleSuMSyBalance,
                    type1::EntryType,
                    entry1::BalanceEntry,
                    sumsy_balance2::SingleSuMSyBalance,
                    type2::EntryType,
                    entry2::BalanceEntry,
                    amount::Real;
                    timestamp::Int = max(get_last_transaction(sumsy_balance1), get_last_transaction(sumsy_balance2)))
    if entry1 === entry2 === SUMSY_DEP && type1 === type2 === asset
        transfer_sumsy!(source, destination, amount, timestamp)
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

function transfer!(sumsy_balance1::SingleSuMSyBalance,
                type1::EntryType,
                sumsy_balance2::SingleSuMSyBalance,
                type2::EntryType,
                entry::BalanceEntry,
                amount::Real;
                timestamp::Int = max(get_last_transaction(sumsy_balance1), get_last_transaction(sumsy_balance2)))
    transfer!(sumsy_balance1, type1, entry, sumsy_balance2, type2, entry, amount, timestamp = timestamp)
end

function transfer_asset!(sumsy_balance1::SingleSuMSyBalance,
                sumsy_balance2::SingleSuMSyBalance,
                entry::BalanceEntry,
                amount::Real;
                timestamp::Int = max(get_last_transaction(sumsy_balance1), get_last_transaction(sumsy_balance2)))
    transfer!(sumsy_balance1, asset, entry, sumsy_balance2, asset, entry, amount, timestamp = timestamp)
end

function transfer_asset!(sumsy_balance1::SingleSuMSyBalance,
                entry1::BalanceEntry,
                sumsy_balance2::SingleSuMSyBalance,
                entry2::BalanceEntry,
                amount::Real;
                timestamp::Int = max(get_last_transaction(sumsy_balance1), get_last_transaction(sumsy_balance2)))
    transfer!(sumsy_balance1, asset, entry1, sumsy_balance2, asset, entry2, amount, timestamp = timestamp)
end

function asset_value(balance::SingleSuMSyBalance, entry::BalanceEntry)
    if entry === SUMSY_DEP
        return sumsy_assets(balance)
    else
        return asset_value(get_balance(balance), entry)
    end
end

function sumsy_assets(sumsy_balance::SingleSuMSyBalance, timestamp::Int = get_last_adjustment(sumsy_balance))
    value = asset_value(get_balance(sumsy_balance), SUMSY_DEP)
    guaranteed_income, demurrage = calculate_adjustments(sumsy_balance, timestamp)

    return value + guaranteed_income - demurrage
end

"""
    adjust_sumsy_balance!(sumsy_balance::SuMSyBalance,
                        sumsy_params::SuMSyParams,
                        timestamp::Int)
"""
function adjust_sumsy_balance!(sumsy_balance::SingleSuMSyBalance, timestamp::Int)
    guaranteed_income, demurrage = calculate_adjustments(sumsy_balance, timestamp)
    set_last_adjustment!(sumsy_balance, timestamp)

    book_asset!(get_balance(sumsy_balance), SUMSY_DEP, guaranteed_income - demurrage, timestamp = timestamp)

    return guaranteed_income, demurrage
end

function calculate_adjustments(sumsy_balance::SingleSuMSyBalance, timestamp::Int, sumsy::SuMSy = sumsy_balance.sumsy)
    timerange = 0

    if is_sumsy_active(sumsy_balance)
        if sumsy.transactional
            timerange = max(0, timestamp - get_last_adjustment(sumsy_balance))
        else         
            timerange = max(0, trunc((timestamp - get_last_adjustment(sumsy_balance)) / sumsy.interval) * sumsy.interval)
        end
    end

    return timerange > 0 ? calculate_timerange_adjustments(sumsy_balance,
                                                            sumsy,
                                                            SUMSY_DEP,
                                                            sumsy_balance.gi_eligible,
                                                            sumsy_balance.dem_free,
                                                            Int(timerange)) : (CUR_0, CUR_0)
end

function reset_sumsy_balance!(sumsy_balance::SingleSuMSyBalance;
                                reset_balance::Bool = true,
                                reset_dem_free::Bool = true,
                                timestamp::Int = get_last_adjustment(sumsy_balance))
    balance = get_balance(sumsy_balance)

    if reset_balance
        if is_gi_eligible(sumsy_balance)
            book_asset!(balance, SUMSY_DEP, get_seed(sumsy_balance), set_to_value = true, timestamp = timestamp)
            book_asset!(balance, SUMSY_DEP, get_guaranteed_income(sumsy_balance), timestamp = timestamp)
        else
            book_asset!(balance, SUMSY_DEP, 0, set_to_value = true, timestamp = timestamp)
        end
    end

    if reset_dem_free
        if is_gi_eligible(sumsy_balance)
            set_dem_free!(sumsy_balance, get_initial_dem_free(sumsy_balance))
        else
            set_dem_free!(sumsy_balance, 0)
        end
    end

    if is_transactional(sumsy_balance)
        set_last_adjustment!(sumsy_balance, timestamp)
    end
end

function set_sumsy!(sumsy_balance::SingleSuMSyBalance,
                    sumsy::SuMSy;
                    reset_balance::Bool = true,
                    reset_dem_free::Bool = true,
                    timestamp::Int = get_last_adjustment(sumsy_balance))
        sumsy_balance.sumsy = sumsy

        reset_sumsy_balance!(sumsy_balance,
                                reset_balance = reset_balance,
                                reset_dem_free = reset_dem_free,
                                timestamp = timestamp)

        return sumsy
end

get_sumsy(sumsy_balance::SingleSuMSyBalance) = sumsy_balance.sumsy

"""
    set_sumsy_active!(sumsy_balance::SingleSuMSyBalance, sumsy::SuMSy, flag::Bool)

Indicate whether the balance participates in the specified SuMSy or not.
"""
function set_sumsy_active!(sumsy_balance::SingleSuMSyBalance, flag::Bool)
    sumsy_balance.sumsy_active = flag
end

function is_sumsy_active(sumsy_balance::SingleSuMSyBalance)
    return sumsy_balance.sumsy_active
end

is_transactional(sumsy_balance::SingleSuMSyBalance) = sumsy_balance.sumsy.transactional

function set_gi_eligible!(sumsy_balance::SingleSuMSyBalance, flag::Bool)
    sumsy_balance.gi_eligible = flag
end

function is_gi_eligible(sumsy_balance::SingleSuMSyBalance)
    return sumsy_balance.gi_eligible
end

function get_seed(sumsy_balance::SingleSuMSyBalance)
    return sumsy_balance.sumsy.income.seed
end

function get_guaranteed_income(sumsy_balance::SingleSuMSyBalance)    
    return sumsy_balance.sumsy.income.guaranteed_income
end

function get_dem_tiers(sumsy_balance::SingleSuMSyBalance)
    return sumsy_balance.sumsy.demurrage.dem_tiers
end

"""
    get_initial_dem_free(sumsy_balance::SingleSuMSyBalance, sumsy::SuMSy)

Returns the initial size of the demurrage free buffer.
"""
function get_initial_dem_free(sumsy_balance::SingleSuMSyBalance)
    return sumsy_balance.sumsy.demurrage.dem_free
end

function set_dem_free!(sumsy_balance::SingleSuMSyBalance, amount::Real)
    sumsy_balance.dem_free = Currency(amount)
end

function get_dem_free(sumsy_balance::SingleSuMSyBalance)
    if is_gi_eligible(sumsy_balance)
        return sumsy_balance.dem_free
    else
        return CUR_0
    end
end

"""
    book_sumsy!(balance::Balance, sumsy::SuMSy, amount::Real, timestamp = 0)

Books an amount on the asset side of the balance, under the SuMSy deposit entry.
If SuMSy is transactional and active for the balance, partial guaranteed income and demurrage are calculated and applied first,
and the timestamp is stored on the balance.
"""
function book_sumsy!(sumsy_balance::SingleSuMSyBalance,
                        amount::Real,
                        timestamp::Int = get_last_transaction(sumsy_balance);
                        set_to_value::Bool = false)
    if !set_to_value && is_transactional(sumsy_balance)
        adjust_sumsy_balance!(sumsy_balance, timestamp)
    end

    book_asset!(get_balance(sumsy_balance), SUMSY_DEP, amount, timestamp = timestamp, set_to_value = set_to_value)
end

"""
    transfer_sumsy!(source::SingleSuMSyBalance,
                    destination::SingleSuMSyBalance,
                    amount::Real,
                    timestamp::Int = 0)

Transfer an amount of SuMSy money from one balance sheet to another. No more than the available amount of money can be transferred.
Negative amounts result in a transfer from destination to source.
"""
function transfer_sumsy!(source::SingleSuMSyBalance,
                        destination::SingleSuMSyBalance,
                        amount::Real,
                        timestamp::Int = max(get_last_transaction(source), get_last_transaction(destination)))
    if is_transactional(source)
        adjust_sumsy_balance!(source, timestamp)
        adjust_sumsy_balance!(destination, timestamp)
    end

    transfer_asset!(get_balance(source), get_balance(destination), SUMSY_DEP, amount, timestamp = timestamp)
end

"""
    transfer_dem_free!(source::Balance, destination::Balance, amount::Real)

Transfer a part or all of the demurrage free buffer from one balance to another. No more than the available demurrage free buffer can be transferred.
If the SuMSy implementation is transaction based, partial guaranteed income and demurrage will be calculated and applied first.
* source::Balance - the balance from which the demurrage free amount is taken.
* destination::Balance - the balance to which the demurrage free buffer is transferred.
* amount::Real - the amount to be transferred.
* return - the amount that was transferred.
"""
function transfer_dem_free!(source::SingleSuMSyBalance,
                            destination::SingleSuMSyBalance,
                            amount::Real,
                            timestamp::Int = max(get_last_adjustment(source), get_last_adjustment(destination)))
    if is_transactional(source)
        adjust_sumsy_balance(source, timestamp)
    end

    if is_transactional(destination)
        adjust_sumsy_balance(destination, timestamp)
    end

    available_dem_free = get_dem_free(source)
    amount = min(amount, available_dem_free)
    set_dem_free!(source, available_dem_free - amount)
    set_dem_free!(destination, get_dem_free(destination) + amount)

    return amount
end

function sumsy_loan!(creditor::SingleSuMSyBalance,
                    debtor::SingleSuMSyBalance,
                    amount::Real,
                    installments::Integer,
                    interval::Int = 1,
                    timestamp::Int = max(get_last_adjustment(creditor), get_last_adjustment(debtor));
                    interest_rate::Real = 0)
    return borrow(get_balance(creditor),
                    get_balance(debtor),
                    amount,
                    interest_rate,
                    installments,
                    interval,
                    timestamp,
                    bank_loan = false,
                    negative_allowed = false,
                    money_entry = SUMSY_DEP,
                    debt_entry = SUMSY_DEBT)
end
