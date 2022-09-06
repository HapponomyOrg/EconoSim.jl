using Todo

import Base: +, -, *, /, <, >, <=, >=, ==, max, min

"""
    Price - a composite price consisting of one or more price components, each associated with a specific balance entry.
"""
struct Price
    components::Dict{BalanceEntry, Currency}
    main_currency::BalanceEntry
    Price(components::Dict{BalanceEntry, <:Real}, main_currency::BalanceEntry) = new(Dict{BalanceEntry, Currency}(components), main_currency)
end

function Price(main_currency::BalanceEntry, amount::Union{Real, Nothing} = nothing)
    if isnothing(amount)
        return Price(Dict{BalanceEntry, Currency}(), main_currency)
    else
        return Price(Dict{BalanceEntry, Currency}(main_currency => amount), main_currency)
    end
end

function Price(components::AbstractVector{<:Pair{BalanceEntry, <:Real}}, main_currency::BalanceEntry = components[1][1])
    Price(Dict{BalanceEntry, Real}(components), main_currency)
end

"""
    ExchangeRates - all available exchange rates.
        Conversion between currencies cooresponding to BalanceEntries are only possible if the exchangerate exists. Exchange rates are not symmetrical.
        Conversion to the main currency is always possible. When no entry for conversion to the main currency is present, parity is assumed.
"""
ExchangeRates = Dict{Tuple{BalanceEntry, BalanceEntry}, Currency}

function get_exhange_rate(exchange_rates::ExchangeRates, from::BalanceEntry, to::BalanceEntry, main_currency::BalanceEntry)
    from_to = (from, to)

    if haskey(exchange_rates, from_to)
        return exchange_rates[from_to]
    elseif to == main_currency
        return Currency(1)
    else
        return Currency(0)
    end
end

Base.isempty(price::Price) = isempty(price.components)
Base.empty(price::Price) = empty(price.components)
Base.empty!(price::Price) = empty!(price.components)
Base.keys(price::Price) = keys(price.components)
Base.values(price::Price) = values(price.components)
Base.getindex(price::Price, index::BalanceEntry) = price.components[index]
Base.setindex!(price::Price, amount::Real, index::BalanceEntry) = (price.components[index] = amount)

function apply_op(price::Price, x::Real, op)
    new_price = Price(price.main_currency)

    for entry in keys(price)
        new_price[entry] = eval(op)(price[entry], x)
    end

    return new_price
end

function apply_op(p1::Price, p2::Price, op)
    entries = union(keys(p1), keys(p2))
    price = Price(precision = max(p1.precision, p2.precision))

    for entry in entries
        price[entry] = round(eval(op)(p1[entry], p2[entry]))
    end

    return price
end

for op in (:+, :-, :*)
    eval(quote
        Base.$op(price::Price, x::Real) = apply_op(price, x, $op)
        Base.$op(x::Real, price::Price) = apply_op(price, x, $op)
    end)

    if op in (:+, :-)
        eval(quote
        Base.$op(p1::Price, p2::Price) = apply_op(p1, p2, $op)
        end)
    end
end

Base.:/(price::Price, x::Real) = apply_op(price, x, :/)

todo"Implement with taking possible exchanges between currencies into account"
function purchases_available(balance::Balance, price::Price, units::Integer; exchange_rates = ExchangeRates())
    max_available = asset_value(balance, price.main_currency) / price[price.main_currency]

    for entry in keys(price)
        if price[entry] != 0
            max_available = min(max_available, asset_value(balance, entry) / price[entry])
        end
    end

    return min(units, Integer(round(Float64(max_available), RoundDown)))
end

"""
    pay!(buyer::Balance,
        seller::Balance,
        price::Price,
        timestamp::Integer;
        comment::String = "")

# Returns
A boolean indicating whether the price was paid in full.
"""
function pay!(buyer::Balance,
            seller::Balance,
            price::Price,
            timestamp::Integer = 0;
            comment::String = "")
    for entry in keys(price)
        queue_asset_transfer!(buyer, seller, entry, price[entry], comment = comment)
    end

    return execute_transfers!(buyer, timestamp)
end
