struct Stock
    stock::Entities
    stock_limits::Dict{Blueprint, Tuple{Int64, Int64}}
    Stock() = new(Entities(), Dict{Blueprint, Tuple{Int64, Int64}}())
end

current_stock(stock::Stock, bp::Blueprint) = num_entities(stock.stock, bp)

function stock_limits(stock::Stock, bp::Blueprint)
    stock_limits = stock.stock_limits

    if bp in keys(stock_limits)
        return stock_limits[bp]
    else
        return (0, 0)
    end
end

stock_limits!(stock::Stock, bp::Blueprint, min_units::Integer, max_units::Integer) = stock.stock_limits[bp] = (min_units, max_units)

min_stock(stock::Stock, bp::Blueprint) = stock_limits(stock, bp)[1]
min_stock!(stock::Stock, bp::Blueprint, units::Integer) = stock_limits!(stock, bp, units, max(units, max_stock(stock, bp)))

max_stock(stock::Stock, bp::Blueprint) = stock_limits(stock, bp)[2]
max_stock!(stock::Stock, bp::Blueprint, units::Integer) = stock_limits!(stock, bp, min(min_stock(stock, bp), units), units)

function add_stock!(stock::Stock,
                products::Union{<:AbstractSet{E}, <:AbstractVector{E}};
                force::Bool = false) where E <: Entity
    for product in collect(products)
        bp = get_blueprint(product)

        if force || current_stock(stock, bp) < max_stock(stock, bp)
            delete_element!(products, product)
            push!(stock.stock, product)
        end
    end

    return stock
end

add_stock!(stock::Stock, product::Entity; force::Bool = false) = add_stock!(stock, [product], force = force)

function retrieve_stock!(stock::Stock, bp::Blueprint, units::Integer)
    products = Set{Entity}()

    if bp in keys(stock.stock)
        i = 0

        for product in collect(stock.stock[bp])
            if i >= units
                break
            end

            delete!(stock.stock, product)
            push!(products, product)
            i += 1
        end
    end

    return products
end

has_stock(stock::Stock, bp::Blueprint) = current_stock(stock, bp) > 0
stocked(stock::Stock, bp::Blueprint) = current_stock(stock, bp) >= min_stock(stock, bp)
overstocked(stock::Stock, bp::Blueprint) = current_stock(stock, bp) > max_stock(stock, bp)

Base.isempty(stock::Stock) = isempty(stock.stock)
Base.empty(stock::Stock) = empty(stock.stock)
Base.empty!(stock::Stock) = empty!(stock.stock)

function purge!(stock::Stock, clear_limits::Bool = false)
    empty!(stock)

    if clear_limits
        empty!(stock.stock_limits)
    end

    return stock
end
