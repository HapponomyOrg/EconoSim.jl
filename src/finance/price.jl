import Base: +, -, *, /, <, >, <=, >=, ==, max, min

"""
    Price - a composite price consisting of one or more price components, each associated with a specific balance entry.
"""
struct Price
    components::Dict{BalanceEntry, Float64}
    precision::Int64
    Price(;precision::Integer = 2) = new(Dict{BalanceEntry, Float64}(), precision)
end

function Price(components::Dict{BalanceEntry, <:Real}; precision::Integer = 2)
    price = Price(precision = precision)

    for entry in keys(components)
        price.components[entry] = round(components[entry], digits = precision)
    end

    return price
end

Price(components::AbstractVector{<:Pair{BalanceEntry, <:Real}}; precision::Integer = 2) = Price(Dict{BalanceEntry, Float64}(components), precision = precision)

Base.isempty(price::Price) = isempty(price.components)
Base.empty(price::Price) = empty(price.components)
Base.empty!(price::Price) = empty!(price.components)
Base.keys(price::Price) = keys(price.components)
Base.values(price::Price) = values(price.components)
Base.getindex(price::Price, index::BalanceEntry) = price.components[index]
Base.setindex!(price::Price, amount::Real, index::BalanceEntry) = (price.components[index] = round(amount, digits = price.precision))

function apply_op(price::Price, x::Real, op)
    new_price = Price(precision = price.precision)

    for entry in keys(price)
        new_price[entry] = round(eval(op)(price[entry], x), digits = price.precision)
    end

    return new_price
end

function apply_op(p1::Price, p2::Price, op)
    entries = union(keys(p1), keys(p2))
    price = Price(precision = max(p1.precision, p2.precision))

    for entry in entries
        price[entry] = round(eval(op)(p1[entry], p2[entry]), digits = price.precision)
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

function purchases_available(balance::Balance, price::Price, units::Integer)
    max_available = INF

    for entry in keys(price)
        if price[entry] != 0
            max_available = min(max_available, round(asset_value(balance, entry) / price[entry], RoundDown))
        end
    end

    return min(units, Integer(max_available))
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
