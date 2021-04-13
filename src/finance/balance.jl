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
    entry::BalanceEntry
    amount::Currency
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
    log_transactions::Bool
    transactions::Vector{Transaction}
    properties::Dict
    Balance(;def_min_asset = 0, def_min_liability = 0, log_transactions = true, properties = Dict()) = new(
                Dict{BalanceEntry, Currency}(),
                def_min_asset,
                Dict{BalanceEntry, Currency}(),
                Dict{BalanceEntry, Currency}(EQUITY => 0),
                def_min_liability,
                Dict{BalanceEntry, Currency}(EQUITY => typemin(Currency)),
                Vector{Transfer{Balance}}(),
                log_transactions,
                Vector{Transaction}(),
                properties)
end

Base.show(io::IO, b::Balance) = print(io, "Balance(\nAssets:\n$(b.assets) \nLiabilities:\n$(b.liabilities) \nTransactions:\n$(b.transactions))")

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

function entry_dict(balance::Balance, type::EntryType)
    if type == asset
        return balance.assets
    else
        return balance.liabilities
    end
end

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
    d = entry_dict(balance, type)

    return e in keys(d) ? d[e] : type == asset ? b.def_min_asset : b.def_min_liability
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
    dict = entry_dict(balance, type)

    if entry in keys(dict)
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
                    amount::Real,
                    timestamp::Integer,
                    comment::String,
                    value_function::Function,
                    transaction::Union{Transaction, Nothing})
    dict = entry_dict(balance, type)

    if entry in keys(dict)
        dict[entry] += amount
    else
        dict[entry] = amount
    end

    balance.liabilities[EQUITY] += type == asset ? amount : -amount

    if balance.log_transactions && amount != 0
        if isnothing(transaction)
            push!(balance.transactions, Transaction(timestamp, asset, entry, amount, value_function(balance, entry), comment))
        else
            push!(transaction, AtomicTransaction(asset, entry, amount, value_function(balance, entry), comment))
        end
    end
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
                    transaction::Union{Transaction, Nothing} = nothing)
    if skip_check || check_booking(b, entry, asset, amount)
        book_amount!(b, entry, asset, amount, timestamp, comment, asset_value, transaction)

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
                        transaction::Union{Transaction, Nothing} = nothing)
    if skip_check || check_booking(b, entry, liability, amount)
        book_amount!(b, entry, liability, amount, timestamp, comment, liability_value, transaction)

        return true
    else
        return false
    end
end

booking_functions = Dict(asset => book_asset!, liability => book_liability!)

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
                transaction1::Union{Transaction, Nothing} = nothing,
                transaction2::Union{Transaction, Nothing} = nothing)
    go = skip_check ? true : check_transfer(b1, type1, b2, type2, entry, amount)

    if go
        booking_functions[type1](b1, entry, -amount, timestamp, comment = comment, skip_check = true, transaction = transaction1)
        booking_functions[type2](b2, entry, amount, timestamp, comment = comment, skip_check = true, transaction = transaction2)
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
    push!(b1.transfer_queue, Transfer(b1, type1, b2, type2, entry, Currency(amount), comment))
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
        t1 = Transaction(timestamp)
        t2 = Transaction(timestamp)

        for transfer in balance.transfer_queue
            transfer!(transfer.source, transfer.source_type, transfer.destination, transfer.destination_type, transfer.entry, transfer.amount, timestamp, comment = transfer.comment, skip_check = true, transaction1 = t1, transaction2 = t2)
        end
    end

    empty!(balance.transfer_queue)

    return go
end
