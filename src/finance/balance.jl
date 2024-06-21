using UUIDs
using Todo

import Base: ==

@enum EntryType asset=1 liability=2

struct BalanceEntry
    id::UUID
    name::Symbol
    BalanceEntry(name::Symbol) = new(uuid4(), name)
end

BalanceEntry(name::String) = BalanceEntry(Symbol(name))

EQUITY = BalanceEntry("Equity")

==(e1::BalanceEntry, e2::BalanceEntry) = e1.id == e2.id

Base.show(io::IO, entry::BalanceEntry) = print(io, "BalanceEntry($(entry.name))")

abstract type AbstractBalance{C <: FixedDecimal} end

"""
    Transfer
Used when working with transactions. All transfers in a transaction must succeed for the transaction to succeed.

* source: the source of the transfer.
* source_type: asset or liability.
* destination: the destination of the transfer.
* destination_type: asset or liability.
* amount: the amount that was transferred.
* entry: the BalanceEntry used in the transfer.
"""
struct Transfer{C <: FixedDecimal, T <: AbstractBalance{C}}
    source::T
    source_type::EntryType
    source_entry::BalanceEntry
    destination::T
    destination_type::EntryType
    destination_entry::BalanceEntry
    amount::C
    timestamp::Int64
end

"""
    struct Balance

A balance sheet, including an optional history of transactions which led to the current state of the balance sheet.

# Properties
* assets: the asset side of the balance sheet.
* def_min_asset: the default lower bound for asset balance entries.
* min_assets: minimum asset values. Used to validate transactions. Entries override def_min_asset.
* liabilities: the liability side of the balance sheet.
* def_min_liability: the default lower bound for liability balance entries.
* min_liabilities: minimum liability values. Used to validate transactions. Entries override def_min_liability.
* transfer_queue: transfers to other balances whcih are queued. When the queue is executed, all transfers are executed in the same transaction.
* properties: a dict with user defined properties. If the key of the dict is a Symbol, the value can be retrieved/set by balance.symbol.
"""
mutable struct Balance{C <: FixedDecimal} <: AbstractBalance{C}
    assets::Dict{BalanceEntry, C}
    def_min_asset::C
    min_assets::Dict{BalanceEntry, C}
    liabilities::Dict{BalanceEntry, C}
    def_min_liability::C
    min_liabilities::Dict{BalanceEntry, C}
    transfer_queue::Vector{Transfer{C, Balance{C}}}
    last_transaction::Int64
    properties::Dict
end

function Balance(;def_min_asset::Real = 0,
                def_min_liability::Real = 0,
                properties = Dict())
    balance = Balance{Currency}(Dict{BalanceEntry, Currency}(),
                        def_min_asset,
                        Dict{BalanceEntry, Currency}(),
                        Dict{BalanceEntry, Currency}(EQUITY => 0),
                        def_min_liability,
                        Dict{BalanceEntry, Currency}(EQUITY => typemin(Currency)),
                        Vector{Transfer{Currency, Balance{Currency}}}(),
                        0,
                        properties)

    return balance
end

Base.show(io::IO, balance::Balance) = print(io, "Balance:\nAssets:\n$(assets(balance))\nLiabilities:\n$(liabilities(balance))")

function Base.getproperty(balance::Balance, s::Symbol)
    properties = getfield(balance, :properties)

    if s in keys(properties)
        return properties[s]
    elseif s in fieldnames(Balance)
        return getfield(balance, s)
    else
        return nothing
    end
end

function Base.setproperty!(balance::Balance, s::Symbol, value)
    if s in fieldnames(Balance)
        setfield!(balance, s, value)
    else
        balance.properties[s] = value
    end

    return value
end

function Base.hasproperty(balance::Balance, s::Symbol)
    return s in fieldnames(Balance) || s in keys(balance.properties)
end

get_balance(balance::Balance) = balance

function entry_dict(balance::Balance, type::EntryType)
    if type == asset
        return balance.assets
    else
        return balance.liabilities
    end
end

has_asset(balance::Balance, entry::BalanceEntry) = haskey(entry_dict(balance, asset), entry)
has_liability(balance::Balance, entry::BalanceEntry) = haskey(entry_dict(balance, liability), entry)

"""
    clear!(balance::Balance)

Sets all assets and liabilities to 0.
"""
function clear!(balance::Balance, reset_last_transaction::Bool = false)
    for type in instances(EntryType)
        dict = entry_dict(balance, type)
        for entry in keys(dict)
            dict[entry] = 0
        end
    end

    if reset_last_transaction
        set_last_transaction!(balance, 0)
    end

    return balance
end

function min_balance!(balance::Balance,
                    entry::BalanceEntry,
                    type::EntryType,
                    amount::Real = 0)
    if entry != EQUITY # Min equity is fixed at typemin(Currency).
        if type == asset
            balance.min_assets[entry] = amount
        else
            balance.min_liabilities[entry] = amount
        end
    end
end

function typemin_balance!(balance::Balance,
                        entry::BalanceEntry,
                        type::EntryType)
    return min_balance!(balance, entry, type, typemin(Currency) + 1)
end

min_asset!(balance::Balance, entry::BalanceEntry, amount::Real = 0) = min_balance!(balance, entry, asset, amount)
typemin_asset!(balance::Balance, entry::BalanceEntry) = typemin_balance!(balance, entry, asset)
min_liability!(balance::Balance, entry::BalanceEntry, amount::Real = 0) = min_balance!(balance, entry, liability, amount)
typemin_liability!(balance::Balance, entry::BalanceEntry) = typemin_balance!(balance, entry, liability)

function min_balance(balance::Balance,
                    entry::BalanceEntry,
                    type::EntryType)
    d = type == asset ? balance.min_assets : balance.min_liabilities

    return entry in keys(d) ? d[entry] : type == asset ? balance.def_min_asset : balance.def_min_liability
end

min_asset(balance::Balance, entry::BalanceEntry) = min_balance(balance, entry, asset)
min_liability(balance::Balance, entry::BalanceEntry) = min_balance(balance, entry, liability)


validate(balance::Balance) = sum(values(balance.assets)) == sum(values(balance.liabilities))
asset_value(balance::Balance, entry::BalanceEntry) = entry_value(balance.assets, entry)
liability_value(balance::Balance, entry::BalanceEntry) = entry_value(balance.liabilities, entry)
assets(balance::Balance) = collect(keys(balance.assets))
liabilities(balance::Balance) = collect(keys(balance.liabilities))
assets_value(balance::Balance) = sum(values(balance.assets))
liabilities_value(balance::Balance) = sum(values(balance.liabilities))
liabilities_net_value(balance::Balance) = liabilities_value(balance) - equity(balance)
equity(balance::Balance) = balance.liabilities[EQUITY]

set_last_transaction!(balance::Balance, timestamp::Int) = (balance.last_transaction = timestamp)
get_last_transaction(balance::Balance) = balance.last_transaction

"""
    entry_value(dict::Dict{BalanceEntry, <: Real},
                entry::BalanceEntry)
"""
function entry_value(dict::Dict{BalanceEntry, <: Real},
                    entry::BalanceEntry)
    if entry in keys(dict)
        return dict[entry]
    else
        return Currency(0)
    end
end

"""
    check_booking(entry::BalanceEntry,
                dict::Dict{BalanceEntry, Currency},
                amount::Real)

# Returns
True if the booking can be executed, false if it violates minimum value constrictions.
"""
function check_booking(balance::Balance,
                    entry::BalanceEntry,
                    type::EntryType,
                    set_to_value::Bool,
                    amount::Real)
    dict = entry_dict(balance, type)

    if !set_to_value && entry in keys(dict)
        new_amount = dict[entry] + amount
    else
        new_amount = amount
    end

    return new_amount >= min_balance(balance, entry, type)
end

"""
    book_amount!(entry::BalanceEntry,
                dict::Dict{BalanceEntry, Currency},
                amount::Real)
"""
function book_amount!(balance::Balance,
                    entry::BalanceEntry,
                    type::EntryType,
                    set_to_value::Bool,
                    amount::Real,
                    timestamp::Int = balance.last_transaction,
                    skip_check::Bool = false)
    if skip_check || check_booking(balance, entry, type, set_to_value, amount)
        dict = entry_dict(balance, type)
        prev_amount = get!(dict, entry, CUR_0)

        if set_to_value
            dict[entry] = amount
            balance.liabilities[EQUITY] += type == asset ? amount - prev_amount : -amount + prev_amount
        else
            dict[entry] += amount
            balance.liabilities[EQUITY] += type == asset ? amount : -amount
        end

        set_last_transaction!(balance, timestamp)

        return true
    else
        return false
    end
end

"""
    book_asset!(balance::Balance,
                entry::BalanceEntry,
                amount::Real,
                timestamp::Integer = 0;
                comment::String = "")

    # Returns
    Whether or not the booking was succesful.
"""
function book_asset!(balance::Balance,
                    entry::BalanceEntry,
                    amount::Real;
                    timestamp::Int = balance.last_transaction,
                    set_to_value = false,
                    skip_check::Bool = false)
    return book_amount!(balance, entry, asset, set_to_value, amount, timestamp, skip_check)
end

"""
    book_liability!(balance::Balance,
                    entry::BalanceEntry,
                    amount::Real,
                    timestamp::Integer = 0;
                    comment::String = "")

        # Returns
        Whether or not the booking was succesful.
"""
function book_liability!(balance::Balance,
                        entry::BalanceEntry,
                        amount::Real;
                        timestamp::Int = balance.last_transaction,
                        set_to_value = false,
                        skip_check::Bool = false)
    return book_amount!(balance, entry, liability, set_to_value, amount, timestamp, skip_check)
end

booking_functions = [book_asset!, book_liability!]

function check_transfer(balance1::Balance,
                type1::EntryType,
                entry1::BalanceEntry,
                balance2::Balance,
                type2::EntryType,
                entry2::BalanceEntry,
                amount::Real)
    if amount >= 0
        return check_booking(balance1, entry1, type1, false, -amount)
    else
        return check_booking(balance2, entry2, type2, false, amount)
    end
end

"""
    transfer!(balance1::Balance,
            type1::EntryType,
            entry1::BalanceEntry,
            balance2::Balance,
            type2::EntryType,
            entry2::BalanceEntry,
            amount::Real,
            timestamp::Integer = 0;
            comment::String = "")
"""
function transfer!(balance1::Balance,
                type1::EntryType,
                entry1::BalanceEntry,
                balance2::Balance,
                type2::EntryType,
                entry2::BalanceEntry,
                amount::Real;
                timestamp::Int = balance.last_transaction,
                skip_check::Bool = false)
    go = skip_check ? true : check_transfer(balance1, type1, entry1, balance2, type2, entry2, amount)

    if go
        booking_functions[Int(type1)](balance1, entry1, -amount, timestamp = timestamp, skip_check = true)
        booking_functions[Int(type2)](balance2, entry2, amount, timestamp = timestamp, skip_check = true)
    end

    return go
end

"""
    transfer!(balance1::Balance,
            type1::EntryType,
            balance2::Balance,
            type2::EntryType,
            entry::BalanceEntry,
            amount::Real,
            timestamp::Integer = 0;
            comment::String = "")
"""
function transfer!(balance1::Balance,
            type1::EntryType,
            balance2::Balance,
            type2::EntryType,
            entry::BalanceEntry,
            amount::Real;
            timestamp::Int = max(balance1.last_transaction, balance2.last_transaction))
    transfer!(balance1, type1, entry, balance2, type2, entry, amount, timestamp = timestamp)
end

"""
    transfer_asset!(balance1::Balance,
                    balance2::Balance,
                    entry::BalanceEntry,
                    amount::Real,
                    timestamp::Integer = 0;
                    comment::String = "")
"""
function transfer_asset!(balance1::Balance,
                    balance2::Balance,
                    entry::BalanceEntry,
                    amount::Real;
                    timestamp::Int = max(balance1.last_transaction, balance2.last_transaction))
    transfer!(balance1, asset, entry, balance2, asset, entry, amount, timestamp = timestamp)
end

"""
    transfer_asset!(balance1::Balance,
                    entry1::BalanceEntry,
                    balance2::Balance,
                    entry2::BalanceEntry,
                    amount::Real,
                    timestamp::Integer = 0;
                    comment::String = "")
"""
function transfer_asset!(balance1::Balance,
                    entry1::BalanceEntry,
                    balance2::Balance,
                    entry2::BalanceEntry,
                    amount::Real;
                    timestamp::Int = max(balance1.last_transaction, balance2.last_transaction))
    transfer!(balance1, asset, entry1, balance2, asset, entry2, amount, timestamp = timestamp)
end

"""
    transfer_liability!(balance1::Balance,
                        balance2::Balance,
                        entry::BalanceEntry,
                        amount::Real,
                        timestamp::Integer = 0;
                        comment::String = "")
"""
function transfer_liability!(balance1::Balance,
                        balance2::Balance,
                        entry::BalanceEntry,
                        amount::Real;
                        timestamp::Int = max(balance1.last_transaction, balance2.last_transaction))
    transfer!(balance1, liability, entry, balance2, liability, entry, amount, timestamp = timestamp)
end

"""
    transfer_liability!(balance1::Balance,
                        entry1::BalanceEntry,
                        balance2::Balance,
                        entry::BalanceEntry,
                        amount::Real,
                        timestamp::Integer = 0;
                        comment::String = "")
"""
function transfer_liability!(balance1::Balance,
                        entry1::BalanceEntry,
                        balance2::Balance,
                        entry2::BalanceEntry,
                        amount::Real;
                        timestamp::Int = max(balance1.last_transaction, balance2.last_transaction))
    transfer!(balance1, liability, entry1, balance2, liability, entry2, amount, timestamp = timestamp)
end

"""
    queue_transfer!(balance1::Balance,
                type1::EntryType,
                balance2::Balance,
                type2::EntryType,
                entry::BalanceEntry,
                amount::Real,
                timestamp::Integer = 0;
                comment::String = "")

Queues a transfer to be executed later. The transfer is queued in the source balance.
"""
function queue_transfer!(balance1::Balance,
                type1::EntryType,
                entry1::BalanceEntry,
                balance2::Balance,
                type2::EntryType,
                entry2::BalanceEntry,
                amount::Real;
                timestamp::Int = max(balance1.last_transaction, balance2.last_transaction))
    push!(balance1.transfer_queue, Transfer(balance1, type1, entry1, balance2, type2, entry2, Currency(amount), timestamp))
end

function queue_asset_transfer!(balance1::Balance,
                            entry1::BalanceEntry,
                            balance2::Balance,
                            entry2::BalanceEntry,
                            amount::Real;
                            timestamp::Int = max(balance1.last_transaction, balance2.last_transaction))
    queue_transfer!(balance1, asset, entry1, balance2, asset, entry2, amount, timestamp = timestamp)
end

function queue_asset_transfer!(balance1::Balance,
                            balance2::Balance,
                            entry::BalanceEntry,
                            amount::Real;
                            timestamp::Int = max(balance1.last_transaction, balance2.last_transaction))
    queue_asset_transfer!(balance1, entry, balance2, entry, amount, timestamp = timestamp)
end

function queue_liability_transfer!(balance1::Balance,
                            entry1::BalanceEntry,
                            balance2::Balance,
                            entry2::BalanceEntry,
                            amount::Real;
                            timestamp::Int = max(balance1.last_transaction, balance2.last_transaction))
    queue_transfer!(balance1, liability, entry1, balance2, liability, entry2, amount, timestamp = timestamp)
end

function queue_liability_transfer!(balance1::Balance,
                            balance2::Balance,
                            entry::BalanceEntry,
                            amount::Real;
                            timestamp::Int = max(balance1.last_transaction, balance2.last_transaction))
    queue_liability_transfer!(balance1, entry, balance2, entry, amount, timestamp = timestamp)
end

function execute_transfers!(balance::Balance)
    go = true

    for transfer in balance.transfer_queue
        go &= check_transfer(transfer.source, transfer.source_type, transfer.source_entry, transfer.destination, transfer.destination_type, transfer.destination_entry, transfer.amount)
    end

    if go
        for transfer in balance.transfer_queue
            transfer!(transfer.source, transfer.source_type, transfer.source_entry,
            transfer.destination, transfer.destination_type, transfer.destination_entry,
            transfer.amount,
            skip_check = true,
            timestamp = transfer.timestamp)
        end
    end

    empty!(balance.transfer_queue)

    return go
end