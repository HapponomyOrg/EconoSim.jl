abstract type Stock end

"""
    PhysicalStock
"""
struct PhysicalStock <: Stock
    stock::Entities
    stock_limits::Dict{Blueprint, Tuple{Int64, Int64}}
    PhysicalStock() = new(Entities(), Dict{Blueprint, Tuple{Int64, Int64}}())
end

current_stock(stock::PhysicalStock, bp::Blueprint) = num_entities(stock.stock, bp)

function stock_limits(stock::PhysicalStock, bp::Blueprint)
    stock_limits = stock.stock_limits

    if bp in keys(stock_limits)
        return stock_limits[bp]
    else
        return (0, 0)
    end
end

stock_limits!(stock::PhysicalStock, bp::Blueprint, min_units::Integer, max_units::Integer) = (stock.stock_limits[bp] = (min_units, max_units))

min_stock(stock::PhysicalStock, bp::Blueprint) = stock_limits(stock, bp)[1]
min_stock!(stock::PhysicalStock, bp::Blueprint, units::Integer) = stock_limits!(stock, bp, units, max(units, max_stock(stock, bp)))

max_stock(stock::PhysicalStock, bp::Blueprint) = stock_limits(stock, bp)[2]
max_stock!(stock::PhysicalStock, bp::Blueprint, units::Integer) = stock_limits!(stock, bp, min(min_stock(stock, bp), units), units)

function add_stock!(stock::PhysicalStock,
                products::Entities;
                force::Bool = false) where E <: Entity
    for bp in keys(products)
        for product in products[bp]
            if add_product(stock, product, force)
                delete!(products, product)
            else
                break
            end
        end
    end

    return stock
end

function add_stock!(stock::PhysicalStock,
                    products::Union{<:AbstractSet{E}, <:AbstractVector{E}};
                    force::Bool = false) where E <: Entity

    for product in collect(products)
        if add_product(stock, product, force)
            delete_element!(products, product)
        end
    end
end

add_stock!(stock::PhysicalStock, product::Entity; force::Bool = false) = add_product(stock, product, force)

function add_product(stock::PhysicalStock, product::Entity, force::Bool)
    bp = get_blueprint(product)

    if force || current_stock(stock, bp) < max_stock(stock, bp)
        push!(stock.stock, product)
        return true
    else
        return false
    end
end

function retrieve_stock!(stock::PhysicalStock, bp::Blueprint, units::Integer)
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

has_stock(stock::PhysicalStock, bp::Blueprint) = current_stock(stock, bp) > 0
stocked(stock::PhysicalStock, bp::Blueprint) = current_stock(stock, bp) >= min_stock(stock, bp)
overstocked(stock::PhysicalStock, bp::Blueprint) = current_stock(stock, bp) > max_stock(stock, bp)

Base.isempty(stock::PhysicalStock) = isempty(stock.stock)
Base.empty(stock::PhysicalStock) = empty(stock.stock)
Base.empty!(stock::PhysicalStock) = empty!(stock.stock)

function purge!(stock::PhysicalStock, clear_limits::Bool = false)
    empty!(stock)

    if clear_limits
        empty!(stock.stock_limits)
    end

    return stock
end

"""
    InfiniteStock
"""
struct InfiniteStock <: Stock
    PhysicalStock() = new()
end

current_stock(stock::InfiniteStock, bp::Blueprint) = INF
stock_limits(stock::InfiniteStock, bp::Blueprint) = INF

stock_limits!(stock::InfiniteStock, bp::Blueprint, min_units::Integer, max_units::Integer) = begin end

min_stock(stock::InfiniteStock, bp::Blueprint) = INF
min_stock!(stock::InfiniteStock, bp::Blueprint, units::Integer) = begin end

max_stock(stock::InfiniteStock, bp::Blueprint) = INF
max_stock!(stock::InfiniteStock, bp::Blueprint, units::Integer) = begin end

add_stock!(stock::InfiniteStock, products::Entities; force::Bool = false) where E <: Entity = stock
add_stock!(stock::InfiniteStock, products::Union{<:AbstractSet{E}, <:AbstractVector{E}}; force::Bool = false) where E <: Entity = stock
add_stock!(stock::InfiniteStock, product::Entity; force::Bool = false) = stock

add_product(stock::InfiniteStock, product::Entity, force::Bool) = true

function retrieve_stock!(stock::InfiniteStock, bp::Blueprint, units::Integer)
    products = Set{Entity}()

    for counter in 1:units
        push!(products, ENTITY_CONSTRUCTORS[bp](bp))
    end

    return products
end

has_stock(stock::PhysiInfiniteStockcalStock, bp::Blueprint) = true
stocked(stock::InfiniteStock, bp::Blueprint) = true
overstocked(stock::InfiniteStock, bp::Blueprint) = false

Base.isempty(stock::InfiniteStock) = false
Base.empty(stock::InfiniteStock) = begin end
Base.empty!(stock::InfiniteStock) = begin end

purge!(stock::InfiniteStock, clear_limits::Bool = false) = stock

