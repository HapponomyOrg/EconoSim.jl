using UUIDs

# TODO Add current balance to transactions
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

struct Transfer{T <: AbstractBalance}
    source::T
    source_type::EntryType
    destination::T
    destination_type::EntryType
    entry::BalanceEntry
    amount::Real
    comment::String
end

"""
    struct Balance

A balance sheet, including a history of transactions which led to the current state of the balance sheet.

* digits: precision
* balance: the balance sheet.
* transactions: a chronological list of transaction tuples. Each tuple is constructed as follows: timestamp, entry type (asset or liability), balance entry, amount, comment.
* properties: a dict with user defined properties. If the key of the dict is a Symbol, the value can be retrieved/set by balance.symbol.
"""
struct Balance <: AbstractBalance
    digits::Int64
    balance::Dict{EntryType, Dict{BalanceEntry, Float64}}
    min_balance::Dict{EntryType, Dict{BalanceEntry, Real}}
    transfer_queue::Vector{Transfer}
    transactions::Vector{Tuple{Int64, EntryType, BalanceEntry, Float64, String}}
    properties::Dict
    Balance(;digits = 2, properties = Dict()) = new(
                digits,
                Dict(asset => Dict{BalanceEntry, Float64}(),
                    liability => Dict{BalanceEntry, Float64}(EQUITY => 0)),
                Dict(asset => Dict{BalanceEntry, Real}(),
                    liability => Dict{BalanceEntry, Real}([EQUITY => -Inf])),
                Vector{Transfer{Balance}}(),
                Vector{Tuple{Int64, EntryType, BalanceEntry, Float64}}(),
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
    if e != EQUITY # Min equity is fixed at -Inf.
        b.min_balance[type][e] = amount
    end
end

min_asset!(b::Balance, e::BalanceEntry, amount::Real = 0) = min_balance!(b, e, asset, amount)
min_liability!(b::Balance, e::BalanceEntry, amount::Real = 0) = min_balance!(b, e, liability, amount)

function min_balance(b::Balance,
                    e::BalanceEntry,
                    type::EntryType)
    d = b.min_balance[type]

    if e in keys(d)
        result = d[e]
    else
        result = 0
    end

    return e in keys(b.min_balance[type]) ? b.min_balance[type][e] : 0
end

min_asset(b::Balance, e::BalanceEntry) = min_balance(b, e, asset)
min_liability(b::Balance, e::BalanceEntry) = min_balance(b, e, liability)


validate(b::Balance) = sum(values(b.balance[asset])) == sum(values(b.balance[liability]))
asset_value(b::Balance, entry::BalanceEntry) = entry_value(b.balance[asset], entry)
liability_value(b::Balance, entry::BalanceEntry) = entry_value(b.balance[liability], entry)
assets(b::Balance) = collect(keys(b.balance[asset]))
liabilities(b::Balance) = collect(keys(b.balance[liability]))
assets_value(b::Balance) = sum(values(b.balance[asset]))
liabilities_value(b::Balance) = sum(values(b.balance[liability]))
liabilities_net_value(b::Balance) = liabilities_value(b) - equity(b)
equity(b::Balance) = b.balance[liability][EQUITY]

"""
    entry_value(dict::Dict{BalanceEntry, Float64},
                entry::BalanceEntry)
"""
function entry_value(dict::Dict{BalanceEntry, Float64},
                    entry::BalanceEntry)
    if entry in keys(dict)
        return dict[entry]
    else
        return Float64(0)
    end
end

"""
    book_amount!(entry::BalanceEntry,
                dict::Dict{BalanceEntry, Float64},
                amount::Real,
                digits::Integer)

Books the amount. Checks on allowance of negative balances need to be made prior to this call.
"""
function book_amount!(entry::BalanceEntry,
                    dict::Dict{BalanceEntry, Float64},
                    amount::Real,
                    digits::Integer)
    if entry in keys(dict)
        dict[entry] = round(dict[entry] + amount, digits = digits)
    else
        dict[entry] = round(amount, digits = digits)
    end
end

"""
    check_booking(entry::BalanceEntry,
                dict::Dict{BalanceEntry, Float64},
                amount::Real,
                negative_allowed::Bool)

# Returns
True if the booking can be executed, false if it violates the negative allowed constriction.
"""
function check_booking(balance::Balance,
                    entry::BalanceEntry,
                    type::EntryType,
                    amount::Real)
    dict = balance.balance[type]

    if entry in keys(dict)
        new_amount = round(dict[entry] + amount, digits = balance.digits)
    else
        new_amount = round(amount, digits = balance.digits)
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
    Whether or not the bokking was succesful.
"""
function book_asset!(b::Balance,
                    entry::BalanceEntry,
                    amount::Real,
                    timestamp::Integer = 0;
                    comment::String = "",
                    skip_check::Bool = false)
    if skip_check || check_booking(b, entry, asset, amount)
        book_amount!(entry, b.balance[asset], amount, b.digits)
        # Negative equity is always allowed!
        book_amount!(EQUITY, b.balance[liability], amount, b.digits)
        if amount != 0
            push!(b.transactions, (timestamp, asset, entry, amount, comment))
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
        Whether or not the bokking was succesful.
"""
function book_liability!(b::Balance,
                        entry::BalanceEntry,
                        amount::Real,
                        timestamp::Integer = 0;
                        comment::String = "",
                        skip_check::Bool = false)
    if skip_check || check_booking(b, entry, liability, amount)
        book_amount!(entry, b.balance[liability], amount, b.digits)
        # Negative equity is always allowed!
        book_amount!(EQUITY, b.balance[liability], -amount, b.digits)
        if amount != 0
            push!(b.transactions, (timestamp, liability, entry, amount, comment))
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
                skip_check::Bool = false)
    go = skip_check ? true : check_transfer(b1, type1, b2, type2, entry, amount)

    if go
        transfer_functions[type1](b1, entry, -amount, timestamp, comment = comment, skip_check = true)
        transfer_functions[type2](b2, entry, amount, timestamp, comment = comment, skip_check = true)
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
        for transfer in balance.transfer_queue
            transfer!(transfer.source, transfer.source_type, transfer.destination, transfer.destination_type, transfer.entry, transfer.amount, timestamp, comment = transfer.comment, skip_check = true)
        end
    end

    empty!(balance.transfer_queue)

    return go
end
