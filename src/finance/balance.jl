using UUIDs

import Base: ==

@enum EntryType asset liability

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
    destination::T
    destination_type::EntryType
    amount::Currency
    entry::BalanceEntry
    comment::String
end

"""
    AtomicTransaction
An atomic transaction.

* type: asset or liability.
* entry: balance entry.
* amount
* balance: balance of the entry after the transaction.
* comment
"""
struct AtomicTransaction
    type::EntryType
    entry::BalanceEntry
    amount::Currency
    balance::Currency
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
    Transaction(timestamp::Integer, type::EntryType, entry::BalanceEntry, amount::Real, balance::Real, comment::String)
Creates a Transaction with 1 Atomictransaction.
"""
function Transaction(timestamp::Integer, type::EntryType, entry::BalanceEntry, amount::Real, balance::Real, comment::String = "")
    t = Transaction(timestamp)
    push!(t, AtomicTransaction(type, entry, amount, balance, comment))

    return t
end

"""
    struct Balance

A balance sheet, including a history of transactions which led to the current state of the balance sheet.

* assets: the asset side of the balance sheet.
* min_assets: minimum asset values. Used to validate transactions.
* liabilities: the liability side of the balance sheet.
* min_liabilities:  minimum liability values. Used to validate transactions.
* transactions: a chronological list of transaction tuples. Each tuple is constructed as follows: timestamp, entry type (asset or liability), balance entry, amount, new balance value, comment.
* properties: a dict with user defined properties. If the key of the dict is a Symbol, the value can be retrieved/set by balance.symbol.
"""
struct Balance <: AbstractBalance
    assets::Dict{BalanceEntry, Currency}
    min_assets::Dict{BalanceEntry, Currency}
    liabilities::Dict{BalanceEntry, Currency}
    min_liabilities::Dict{BalanceEntry, Currency}
    transfer_queue::Vector{Transfer}
    transactions::Vector{Transaction}
    properties::Dict
    Balance(;properties = Dict()) = new(
                Dict(BalanceEntry, Currency}(),
                Dict(BalanceEntry, Currency}(),
                Dict(BalanceEntry, Currency}(EQUITY => 0),
                Dict(BalanceEntry, Currency}(EQUITY => typemin(Currency)),
                Vector{Transfer{Balance}}(),
                Vector{Transaction}(),
                properties)
end

Base.show(io::IO, b::Balance) = print(io, "Balance(\nAssets:\n$(b.balance[asset]) \nLiabilities:\n$(b.balance[liability]) \nTransactions:\n$(b.transactions))")

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

function min_balance!(b::Balance,
                    e::BalanceEntry,
                    type::EntryType,
                    amount::Real = 0)
    if e != EQUITY # Min equity is fixed at typemin(Currency).
        if type == asset
            b.min_assets[e] = amount
        else
            b.min_liabilities[e] = amount
        end
    end
end

min_asset!(b::Balance, e::BalanceEntry, amount::Real = 0) = min_balance!(b, e, asset, amount)
min_liability!(b::Balance, e::BalanceEntry, amount::Real = 0) = min_balance!(b, e, liability, amount)

function min_balance(b::Balance,
                    e::BalanceEntry,
                    type::EntryType)
    d = type == asset ? b.min_assets : b.min_liabilities

    return e in keys(d) ? d[e] : Currency(0)
end

min_asset(b::Balance, e::BalanceEntry) = min_balance(b, e, asset)
min_liability(b::Balance, e::BalanceEntry) = min_balance(b, e, liability)


validate(b::Balance) = sum(values(b.assets)) == sum(values(b.liabilities))
asset_value(b::Balance, entry::BalanceEntry) = entry_value(b.assets, entry)
liability_value(b::Balance, entry::BalanceEntry) = entry_value(b.liabilities, entry)
assets(b::Balance) = collect(keys(b.assets))
liabilities(b::Balance) = collect(keys(b.liabilities))
assets_value(b::Balance) = sum(values(b.assets))
liabilities_value(b::Balance) = sum(values(b.liabilities))
liabilities_net_value(b::Balance) = liabilities_value(b) - equity(b)
equity(b::Balance) = b.liabilities[EQUITY]

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
    book_amount!(entry::BalanceEntry,
                dict::Dict{BalanceEntry, Currency},
                amount::Real)

Books the amount. Checks on allowance of negative balances need to be made prior to this call.
"""
function book_amount!(entry::BalanceEntry,
                    dict::Dict{BalanceEntry, Currency},
                    amount::Real)
    if entry in keys(dict)
        dict[entry] = dict[entry] + amount
    else
        dict[entry] = amount
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
                    amount::Real)
    dict = type == asset ? balance.assets : balance.liabilities

    if entry in keys(dict)
        new_amount = dict[entry] + amount
    else
        new_amount = amount
    end

    return new_amount >= min_balance(balance, entry, type)
end

"""
    book_asset!(b::Balance,
                entry::BalanceEntry,
                amount::Real,
                timestamp::Integer = 0;
                comment::String = "")

    # Returns
    Whether or not the booking was succesful.
"""
function book_asset!(b::Balance,
                    entry::BalanceEntry,
                    amount::Real,
                    timestamp::Integer = 0;
                    comment::String = "",
                    skip_check::Bool = false,
                    new_transaction::Bool = true)
    if skip_check || check_booking(b, entry, asset, amount)
        book_amount!(entry, b.assets, amount)
        # Negative equity is always allowed!
        book_amount!(EQUITY, b.liabilities, amount)

        if amount != 0
            if new_transaction
                push!(b.transactions, Transaction(timestamp, asset, entry, amount, asset_value(b, entry), comment))
            else
                push!(last(b.transactions, AtomicTransaction(asset, entry, amount, asset_value(b, entry), comment)))
            end
        end

        return true
    else
        return false
    end
end

"""
    book_liability!(b::Balance,
                    entry::BalanceEntry,
                    amount::Real,
                    timestamp::Integer = 0;
                    comment::String = "")

        # Returns
        Whether or not the booking was succesful.
"""
function book_liability!(b::Balance,
                        entry::BalanceEntry,
                        amount::Real,
                        timestamp::Integer = 0;
                        comment::String = "",
                        skip_check::Bool = false,
                        new_transaction::Bool = true)
    if skip_check || check_booking(b, entry, liability, amount)
        book_amount!(entry, b.liabilities, amount)
        # Negative equity is always allowed!
        book_amount!(EQUITY, b.liabilities, -amount)

        if amount != 0
            if new_transaction
                push!(b.transactions, Transaction(timestamp, asset, entry, amount, liability_value(b, entry), comment))
            else
                push!(last(b.transactions, AtomicTransaction(asset, entry, amount, liability_value(b, entry), comment)))
            end
        end

        return true
    else
        return false
    end
end

function check_transfer(b1::Balance,
                type1::EntryType,
                b2::Balance,
                type2::EntryType,
                entry::BalanceEntry,
                amount::Real)
    if amount >= 0
        return check_booking(b1, entry, type1, -amount)
    else
        return check_booking(b2, entry, type2, amount)
    end
end

transfer_functions = Dict(asset => book_asset!, liability => book_liability!)
value_functions = Dict(asset => asset_value, liability => liability_value)

"""
    transfer!(b1::Balance,
            type1::EntryType,
            b2::Balance,
            type2::EntryType,
            entry::BalanceEntry,
            amount::Real,
            timestamp::Integer = 0;
            comment::String = "")
"""
function transfer!(b1::Balance,
                type1::EntryType,
                b2::Balance,
                type2::EntryType,
                entry::BalanceEntry,
                amount::Real,
                timestamp::Integer = 0;
                comment::String = "",
                skip_check::Bool = false,
                new_transaction::Bool = true)
    go = skip_check ? true : check_transfer(b1, type1, b2, type2, entry, amount)

    if go
        transfer_functions[type1](b1, entry, -amount, timestamp, comment = comment, skip_check = true, new_transaction = new_transaction)
        transfer_functions[type2](b2, entry, amount, timestamp, comment = comment, skip_check = true, new_transaction = new_transaction)
    end

    return go
end

"""
    transfer_asset!(b1::Balance,
                    b2::Balance,
                    entry::BalanceEntry,
                    amount::Real,
                    timestamp::Integer = 0;
                    comment::String = "")
"""
function transfer_asset!(b1::Balance,
                        b2::Balance,
                        entry::BalanceEntry,
                        amount::Real,
                        timestamp::Integer = 0;
                        comment::String = "")
    transfer!(b1, asset, b2, asset, entry, amount, timestamp, comment = comment)
end

"""
    transfer_liability!(b1::Balance,
                        b2::Balance,
                        entry::BalanceEntry,
                        amount::Real,
                        timestamp::Integer = 0;
                        comment::String = "")
"""
function transfer_liability!(b1::Balance,
                            b2::Balance,
                            entry::BalanceEntry,
                            amount::Real,
                            timestamp::Integer = 0;
                            comment::String = "")
    transfer!(b1, liability, b2, liability, entry, amount, timestamp, comment = comment)
end

"""
    queue_transfer!(b1::Balance,
                type1::EntryType,
                b2::Balance,
                type2::EntryType,
                entry::BalanceEntry,
                amount::Real,
                timestamp::Integer = 0;
                comment::String = "")

Queues a transfer to be executed later. The transfer is queued in the source balance.
"""
function queue_transfer!(b1::Balance,
                type1::EntryType,
                b2::Balance,
                type2::EntryType,
                entry::BalanceEntry,
                amount::Real;
                comment::String = "")
    push!(b1.transfer_queue, Transfer(b1, type1, b2, type2, entry, amount, comment))
end

function queue_asset_transfer!(b1::Balance,
                            b2::Balance,
                            entry::BalanceEntry,
                            amount::Real;
                            comment::String = "")
    queue_transfer!(b1, asset, b2, asset, entry, amount, comment = comment)
end

function queue_liability_transfer!(b1::Balance,
                            b2::Balance,
                            entry::BalanceEntry,
                            amount::Real;
                            comment::String = "")
    queue_transfer!(b1, liability, b2, liability, entry, amount, comment = comment)
end

function execute_transfers!(balance::Balance, timestamp::Integer = 0)
    go = true

    for transfer in balance.transfer_queue
        go &= check_transfer(transfer.source, transfer.source_type, transfer.destination, transfer.destination_type, transfer.entry, transfer.amount)
    end

    if go
        new_transaction = true

        for transfer in balance.transfer_queue
            transfer!(transfer.source, transfer.source_type, transfer.destination, transfer.destination_type, transfer.entry, transfer.amount, timestamp, comment = transfer.comment, skip_check = true, new_transaction = new_transaction)

            new_transaction = false
        end
    end

    empty!(balance.transfer_queue)

    return go
end
