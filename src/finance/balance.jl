using UUIDs
using Todo

import Base: ==

todo"Move comments to seperate functions"

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

abstract type AbstractBalance end

"""
    Transfer
Used when working with transactions. All transfers in a transaction must succeed for the transaction to succeed.

* source: the source of the transfer.
* source_type: asset or liability.
* destination: the destination of the transfer.
* destination_type: asset or liability.
* amount: the amount that was transferred.
* entry: the BalanceEntry used in the transfer.
* comment
"""
struct Transfer{T <: AbstractBalance}
    source::T
    source_type::EntryType
    source_entry::BalanceEntry
    destination::T
    destination_type::EntryType
    destination_entry::BalanceEntry
    amount::Currency
    comment::String
end

"""
    AtomicTransaction
An atomic transaction.

* type: asset or liability.
* entry: balance entry.
* amount: amount of the transaction.
* result: result of the transaction. The new balance amount of the entry.
* comment
"""
struct AtomicTransaction
    type::EntryType
    entry::BalanceEntry
    amount::Currency
    result::Currency
    comment::String
end

"""
    Transaction
A timestamped list of atomic transactions which have been executed in batch.
"""
struct Transaction
    timestamp::Int64
    transactions::Vector{AtomicTransaction}
    Transaction(timestamp::Integer) = new(timestamp, Vector{AtomicTransaction}())
end

Base.push!(transaction::Transaction, at::AtomicTransaction) = push!(transaction.transactions, at)

"""
    Transaction(timestamp::Integer, type::EntryType, entry::BalanceEntry, amount::Real, result::Real, comment::String)
Creates a Transaction with 1 Atomictransaction.
"""
function Transaction(timestamp::Integer, type::EntryType, entry::BalanceEntry, amount::Real, result::Real, comment::String = "")
    t = Transaction(timestamp)
    push!(t, AtomicTransaction(type, entry, amount, result, comment))

    return t
end

"""
    struct Balance

A balance sheet, including a history of transactions which led to the current state of the balance sheet.

# Properties
* assets: the asset side of the balance sheet.
* def_min_asset: the default lower bound for asset balance entries.
* min_assets: minimum asset values. Used to validate transactions. Entries override def_min_asset.
* liabilities: the liability side of the balance sheet.
* def_min_liability: the default lower bound for liability balance entries.
* min_liabilities:  minimum liability values. Used to validate transactions. Entries override def_min_liability.
* log_transactions: flag indicating whether transactions are logged. Not logging transactions improves performance.
* transactions: a chronological list of transaction tuples. Each tuple is constructed as follows: timestamp, entry type (asset or liability), balance entry, amount, new balance value, comment.
* properties: a dict with user defined properties. If the key of the dict is a Symbol, the value can be retrieved/set by balance.symbol.
"""
struct Balance <: AbstractBalance
    assets::Dict{BalanceEntry, Currency}
    def_min_asset::Currency
    min_assets::Dict{BalanceEntry, Currency}
    liabilities::Dict{BalanceEntry, Currency}
    def_min_liability::Currency
    min_liabilities::Dict{BalanceEntry, Currency}
    transfer_queue::Vector{Transfer}
    trigger_actions::Union{Nothing, Function, Vector{Function}}
    properties::Dict
    Balance(;def_min_asset = 0, def_min_liability = 0, trigger_actions = nothing, properties = Dict()) = new(
                Dict{BalanceEntry, Currency}(),
                def_min_asset,
                Dict{BalanceEntry, Currency}(),
                Dict{BalanceEntry, Currency}(EQUITY => 0),
                def_min_liability,
                Dict{BalanceEntry, Currency}(EQUITY => typemin(Currency)),
                Vector{Transfer{Balance}}(),
                trigger_actions,
                properties)
end

Base.show(io::IO, balance::Balance) = print(io, "Balance(\nAssets:\n$(balance.assets) \nLiabilities:\n$(balance.liabilities) \nTransactions:\n$(balance.transactions))")

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
function clear!(balance::Balance)
    for type in instances(EntryType)
        dict = entry_dict(balance, type)
        for entry in keys(dict)
            dict[entry] = 0
        end
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

min_asset!(balance::Balance, entry::BalanceEntry, amount::Real = 0) = min_balance!(balance, entry, asset, amount)
min_liability!(balance::Balance, entry::BalanceEntry, amount::Real = 0) = min_balance!(balance, entry, liability, amount)

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

"""
    entry_value(dict::Dict{BalanceEntry, Currency},
                entry::BalanceEntry)
"""
function entry_value(dict::Dict{BalanceEntry, Currency},
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

Books the amount. Checks on allowance of negative balances need to be made prior to this call.
"""
function book_amount!(balance::Balance,
                    entry::BalanceEntry,
                    type::EntryType,
                    set_to_value::Bool,
                    amount::Real,
                    timestamp::Integer,
                    comment::String,
                    value_function::Function,
                    transaction::Union{Transaction, Nothing})
    dict = entry_dict(balance, type)

    if !set_to_value && entry in keys(dict)
        dict[entry] += amount
    else
        dict[entry] = amount
    end

    balance.liabilities[EQUITY] += type == asset ? amount : -amount

    trigger(balance, entry, type, amount, timestamp, comment, value_function(balance, entry), transaction)
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
                    amount::Real,
                    timestamp::Integer = 0;
                    set_to_value = false,
                    comment::String = "",
                    skip_check::Bool = false,
                    transaction::Union{Transaction, Nothing} = nothing)
    if skip_check || check_booking(balance, entry, asset, set_to_value, amount)
        book_amount!(balance, entry, asset, set_to_value, amount, timestamp, comment, asset_value, transaction)

        return true
    else
        return false
    end
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
                        amount::Real,
                        timestamp::Integer = 0;
                        set_to_value = false,
                        comment::String = "",
                        skip_check::Bool = false,
                        transaction::Union{Transaction, Nothing} = nothing)
    if skip_check || check_booking(balance, entry, liability, set_to_value, amount)
        book_amount!(balance, entry, liability, set_to_value, amount, timestamp, comment, liability_value, transaction)

        return true
    else
        return false
    end
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
                amount::Real,
                timestamp::Integer = 0;
                comment::String = "",
                skip_check::Bool = false,
                transaction1::Union{Transaction, Nothing} = nothing,
                transaction2::Union{Transaction, Nothing} = nothing)
    go = skip_check ? true : check_transfer(balance1, type1, entry1, balance2, type2, entry2, amount)

    if go
        booking_functions[Int(type1)](balance1, entry1, -amount, timestamp, comment = comment, skip_check = true, transaction = transaction1)
        booking_functions[Int(type2)](balance2, entry2, amount, timestamp, comment = comment, skip_check = true, transaction = transaction2)
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
                amount::Real,
                timestamp::Integer = 0;
                comment::String = "",
                skip_check::Bool = false,
                transaction1::Union{Transaction, Nothing} = nothing,
                transaction2::Union{Transaction, Nothing} = nothing)
    transfer!(balance1, type1, entry, balance2, type2, entry, amount, timestamp,
            comment = comment, skip_check = skip_check,
            transaction1 = transaction1, transaction2 = transaction2)
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
                        amount::Real,
                        timestamp::Integer = 0;
                        comment::String = "")
    transfer!(balance1, asset, entry, balance2, asset, entry, amount, timestamp, comment = comment)
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
                        amount::Real,
                        timestamp::Integer = 0;
                        comment::String = "")
    transfer!(balance1, asset, entry1, balance2, asset, entry2, amount, timestamp, comment = comment)
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
                            amount::Real,
                            timestamp::Integer = 0;
                            comment::String = "")
    transfer!(balance1, liability, entry, balance2, liability, entry, amount, timestamp, comment = comment)
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
                            amount::Real,
                            timestamp::Integer = 0;
                            comment::String = "")
    transfer!(balance1, liability, entry1, balance2, liability, entry2, amount, timestamp, comment = comment)
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
                comment::String = "")
    push!(balance1.transfer_queue, Transfer(balance1, type1, entry1, balance2, type2, entry2, Currency(amount), comment))
end

function queue_asset_transfer!(balance1::Balance,
                            entry1::BalanceEntry,
                            balance2::Balance,
                            entry2::BalanceEntry,
                            amount::Real;
                            comment::String = "")
    queue_transfer!(balance1, asset, entry1, balance2, asset, entry2, amount, comment = comment)
end

function queue_asset_transfer!(balance1::Balance,
                            balance2::Balance,
                            entry::BalanceEntry,
                            amount::Real;
                            comment::String = "")
    queue_asset_transfer!(balance1, entry, balance2, entry, amount, comment = comment)
end

function queue_liability_transfer!(balance1::Balance,
                            entry1::BalanceEntry,
                            balance2::Balance,
                            entry2::BalanceEntry,
                            amount::Real;
                            comment::String = "")
    queue_transfer!(balance1, liability, entry1, balance2, liability, entry2, amount, comment = comment)
end

function queue_liability_transfer!(balance1::Balance,
                            balance2::Balance,
                            entry::BalanceEntry,
                            amount::Real;
                            comment::String = "")
    queue_liability_transfer!(balance1, entry, balance2, entry, amount, comment = comment)
end

function execute_transfers!(balance::Balance, timestamp::Integer = 0)
    go = true

    for transfer in balance.transfer_queue
        go &= check_transfer(transfer.source, transfer.source_type, transfer.source_entry, transfer.destination, transfer.destination_type, transfer.destination_entry, transfer.amount)
    end

    if go
        t1 = Transaction(timestamp)
        t2 = Transaction(timestamp)

        for transfer in balance.transfer_queue
            transfer!(transfer.source, transfer.source_type, transfer.source_entry, transfer.destination, transfer.destination_type, transfer.destination_entry, transfer.amount, timestamp, comment = transfer.comment, skip_check = true, transaction1 = t1, transaction2 = t2)
        end
    end

    empty!(balance.transfer_queue)

    return go
end

# Log trigger
function initialize_logging(b::Balance)
    b.transaction_log = Vector{Transaction}()

    return log_transaction
end

function log_transaction(balance::Balance,
                        entry::BalanceEntry,
                        type::EntryType,
                        amount::Real,
                        timestamp::Integer,
                        comment::String,
                        value::Currency,
                        transaction::Union{Transaction, Nothing})
    if amount != 0
        if isnothing(transaction)
            push!(balance.transaction_log, Transaction(timestamp, asset, entry, amount, value, comment))
        else
            push!(transaction, AtomicTransaction(asset, entry, amount, value, comment))
        end
    end
end