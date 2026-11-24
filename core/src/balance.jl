# Concrete double-entry balance sheets.
#
# A `Balance` owns one `Money` slot per `Entry` on each side. Booking an asset
# increases equity; booking a liability decreases it, so the sheet stays
# balanced (`sum(assets) == sum(liabilities)`).
#
# There are no dictionaries, symbols, UUIDs, or property bags in the core.

mutable struct Balance
    assets::Vector{Money}
    liabilities::Vector{Money}
    min_assets::Vector{Money}
    min_liabilities::Vector{Money}
    last_transaction::Int64
    count::Int32
end

"""
    Balance(; schema = DEFAULT_LEDGER_SCHEMA, def_min_asset = 0,
              def_min_liability = 0, last_transaction = 0)

Create a zeroed balance sheet with `schema.count` active entries. Equity may go
negative by default; other liabilities default to the supplied minimum.
"""
function Balance(; schema::LedgerSchema = DEFAULT_LEDGER_SCHEMA,
                   def_min_asset::Money = MONEY_ZERO,
                   def_min_liability::Money = MONEY_ZERO,
                   last_transaction::Integer = 0)
    count = Int(schema.count)
    assets = fill(MONEY_ZERO, count)
    liabilities = fill(MONEY_ZERO, count)
    min_assets = Vector{Money}(undef, count)
    min_liabilities = Vector{Money}(undef, count)
    for i in 1:count
        min_assets[i] = def_min_asset
        min_liabilities[i] = def_min_liability
    end
    min_liabilities[entry_index(EQUITY)] = typemin(Money)
    return Balance(assets, liabilities, min_assets, min_liabilities,
                   Int64(last_transaction), schema.count)
end

function clear!(balance::Balance, reset_last_transaction::Bool = false)
    fill!(balance.assets, MONEY_ZERO)
    fill!(balance.liabilities, MONEY_ZERO)
    reset_last_transaction && (balance.last_transaction = 0)
    return balance
end

@inline asset_value(balance::Balance, entry::Entry) = balance.assets[entry_index(entry)]
@inline liability_value(balance::Balance, entry::Entry) = balance.liabilities[entry_index(entry)]

@inline assets_value(balance::Balance) = sum(balance.assets)
@inline liabilities_value(balance::Balance) = sum(balance.liabilities)
@inline equity(balance::Balance) = balance.liabilities[entry_index(EQUITY)]
@inline validate(balance::Balance) = assets_value(balance) == liabilities_value(balance)

function def_min_asset!(balance::Balance, amount::Money = MONEY_ZERO)
    for i in 1:balance.count
        balance.min_assets[i] = amount
    end
    return balance
end

function def_min_liability!(balance::Balance, amount::Money = MONEY_ZERO)
    for i in 1:balance.count
        balance.min_liabilities[i] = amount
    end
    balance.min_liabilities[entry_index(EQUITY)] = typemin(Money)
    return balance
end

function min_asset!(balance::Balance, entry::Entry, amount::Money = MONEY_ZERO)
    balance.min_assets[entry_index(entry)] = amount
    return balance
end

function min_liability!(balance::Balance, entry::Entry, amount::Money = MONEY_ZERO)
    entry === EQUITY && return balance
    balance.min_liabilities[entry_index(entry)] = amount
    return balance
end

typemin_asset!(balance::Balance, entry::Entry) =
    min_asset!(balance, entry, Money(typemin(Int64) + 1))
typemin_liability!(balance::Balance, entry::Entry) =
    min_liability!(balance, entry, Money(typemin(Int64) + 1))

@inline function _can_book(balance::Balance, entry::Entry, is_asset::Bool,
                           amount::Money, set_to_value::Bool)
    idx = entry_index(entry)
    current = is_asset ? balance.assets[idx] : balance.liabilities[idx]
    new_value = set_to_value ? amount : current + amount
    minimum = is_asset ? balance.min_assets[idx] : balance.min_liabilities[idx]
    return new_value >= minimum
end

function _book!(balance::Balance, entry::Entry, is_asset::Bool, amount::Money;
                set_to_value::Bool = false,
                timestamp::Integer = balance.last_transaction,
                skip_check::Bool = false)
    if !skip_check && !_can_book(balance, entry, is_asset, amount, set_to_value)
        return false
    end

    idx = entry_index(entry)
    if is_asset
        current = balance.assets[idx]
        new_value = set_to_value ? amount : current + amount
        delta = new_value - current
        balance.assets[idx] = new_value
        balance.liabilities[entry_index(EQUITY)] =
            balance.liabilities[entry_index(EQUITY)] + delta
    else
        current = balance.liabilities[idx]
        new_value = set_to_value ? amount : current + amount
        delta = new_value - current
        balance.liabilities[idx] = new_value
        balance.liabilities[entry_index(EQUITY)] =
            balance.liabilities[entry_index(EQUITY)] - delta
    end

    balance.last_transaction = Int64(timestamp)
    return true
end

"""
    book_asset!(balance, entry, amount; set_to_value=false, timestamp=..., skip_check=false)

Book an amount on the asset side. Returns `false` if the booking would violate
the entry's minimum.
"""
book_asset!(balance::Balance, entry::Entry, amount::Money; kwargs...) =
    _book!(balance, entry, true, amount; kwargs...)

"""
    book_liability!(balance, entry, amount; set_to_value=false, timestamp=..., skip_check=false)

Book an amount on the liability side. Returns `false` if the booking would
violate the entry's minimum.
"""
book_liability!(balance::Balance, entry::Entry, amount::Money; kwargs...) =
    _book!(balance, entry, false, amount; kwargs...)

"""
    transfer!(source, source_type, source_entry, destination, destination_type,
              destination_entry, amount; timestamp=..., skip_check=false)

Move an amount between two balance sheets. Both sides are checked before
anything is booked, so a failed transfer leaves both sheets unchanged.
"""
function transfer!(source::Balance, source_side::Side, source_entry::Entry,
                   destination::Balance, destination_side::Side,
                   destination_entry::Entry, amount::Money;
                   timestamp::Integer = max(source.last_transaction,
                                            destination.last_transaction),
                   skip_check::Bool = false)
    source_is_asset = source_side === ASSET
    destination_is_asset = destination_side === ASSET

    if !skip_check &&
       (!_can_book(source, source_entry, source_is_asset, -amount, false) ||
        !_can_book(destination, destination_entry, destination_is_asset, amount, false))
        return false
    end

    _book!(source, source_entry, source_is_asset, -amount;
           timestamp = timestamp, skip_check = true)
    _book!(destination, destination_entry, destination_is_asset, amount;
           timestamp = timestamp, skip_check = true)
    return true
end

# Convenience wrappers for the common same-side transfers.
transfer_asset!(source::Balance, destination::Balance, entry::Entry, amount::Money; kwargs...) =
    transfer!(source, ASSET, entry, destination, ASSET, entry, amount; kwargs...)

transfer_liability!(source::Balance, destination::Balance, entry::Entry, amount::Money; kwargs...) =
    transfer!(source, LIABILITY, entry, destination, LIABILITY, entry, amount; kwargs...)

function Base.show(io::IO, balance::Balance)
    print(io, "Balance(assets=", assets_value(balance),
          ", liabilities=", liabilities_value(balance),
          ", equity=", equity(balance), ")")
end

export Balance, clear!, asset_value, liability_value, assets_value, liabilities_value
export equity, validate, def_min_asset!, def_min_liability!, min_asset!, min_liability!
export typemin_asset!, typemin_liability!
export book_asset!, book_liability!, transfer!, transfer_asset!, transfer_liability!
