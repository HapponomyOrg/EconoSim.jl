using Agents

Prices = Dict{<:Blueprint, Price}

"""
    EconomicActor - agent representing a full economic actor.

# Fields
* id::Int - the id of the actor.
* types::Set{Symbol} - the types of the actor. Types are meant to be used in data collection and/or behavior functions.
* behaviors::Vector{Function} - the list of behavior functions which is called when the actor is activated.
* balance::Balance - the balance sheet of the actor.
* posessions::Entities - the entities in personal posession of the actor.
* stock::Stock - the stock held by the actor. The stock is considered to be used for business purposes.
* producers::Set{Producer} - the production facilities of the actor.
* prices::D where D <: Dict{<:Blueprint, Price} - the prices of the products sold by the actor.
* properties::Dict{Symbol, Any} - for internal use.

After creation, any field can be set on the actor, even those which are not part of the structure. This can come in handy when when specific state needs to be stored with the actor.
"""
mutable struct EconomicActor <: AbstractActor
    id::Int64
    types::Set{Symbol}
    behaviors::Vector{Function}
    balance::AbstractBalance
    posessions::Entities
    stock::Stock
    producers::Set{Producer}
    prices::Prices
    properties::D where {D <: Dict{Symbol, <:Any}}
end

"""
EconomicActor - creation function for a generic actor.

# Parameters
* id::Int = ID_COUNTER - the id of the actor. When no id is given, the standard sequence of id's is used. Mixing the standard sequence and user defined id's is not advised.
* type::Union{Symbol, Nothing} = nothing - the types of the actor. Types are meant to be used in data collection and/or behavior functions.
* behavior::Union{Function, Nothing} = nothing - the default behavior function which is called when the actor is activated.
* balance::Balance = Balance() - the balance sheet of the actor.
* posessions::Entities = Entities() - the entities in personal posession of the actor.
* stock::Stock = Stock() - the stock held by the actor. The stock is considered to be used for business purposes.
* producers::Union{AbstractVector{Producer}, AbstractSet{Producer}} = Set{Producer}() - the production facilities of the actor.
"""
function EconomicActor(id::Int64;
        types::Union{Set{Symbol}, Symbol, Nothing} = nothing,
        behaviors::Union{Vector{Function}, Function, Nothing} = nothing,
        balance::AbstractBalance = Balance(),
        posessions::Entities = Entities(),
        stock::Stock = PhysicalStock(),
        producers::Union{AbstractVector{Producer}, AbstractSet{Producer}} = Set{Producer}(),
        prices::D = Dict{Blueprint, Price}()) where {D <: Prices}
    if isnothing(types)
        typeset = Set{Symbol}()
    elseif types isa Symbol
        typeset = Set([types])
    else
        typeset = types
    end

    if isnothing(behaviors)
        actor_behaviors = Vector{Function}()
    elseif behaviors isa Function
        actor_behaviors = Vector([behavior])
    else
        actor_behaviors = behaviors
    end

    actor = EconomicActor(id,
                            typeset,
                            actor_behaviors,
                            balance,
                            posessions,
                            stock,
                            Set(producers),
                            prices,
                            Dict{Symbol, Any}())

    return actor
end

push_producer!(actor::EconomicActor, producer::Producer) = (push!(actor.producers, producer); actor)
delete_producer!(actor::EconomicActor, producer::Producer) = (delete!(actor.producers, producer); actor)

get_posessions(actor::EconomicActor, bp::Blueprint) = bp in keys(actor.posessions) ? length(actor.posessions[bp]) : 0
get_stock(actor::EconomicActor, bp::Blueprint) = current_stock(actor.stock, bp)

"""
    get_production_output(actor::Actor)

Get the set of all blueprints produced by the actor.
"""
function get_production_output(actor::EconomicActor)
    production = Set{Blueprint}()

    for producer in keys(actor.producers)
        production = union(Set(keys(get_blueprint(producer).batch)), production)
    end

    return production
end

set_price!(actor::EconomicActor, bp::Blueprint, price::Price) = (actor.prices[bp] = price; actor)
get_price(actor::EconomicActor, bp::Blueprint) = haskey(actor.prices, bp) ? actor.prices[bp] : nothing
get_price(model, actor::EconomicActor, bp::Blueprint) = isnothing(get_price(actor, bp)) ? get_price(model, bp) : get_price(actor, bp)

"""
    purchase!(model::ABM, buyer::EconomicActor, seller::EconomicActor, bp::Blueprint, units::Integer, pre_sales::Function...)

Atempt to purchase a number of units from the seller.

* model::ABM
* buyer::EconomicActor
* seller::EconomicActor
* bp::Blueprint
* units::Integer
* pre_sales::Function : functions which need to be executed before a sale takes place. These functions need to have the following signature:
    pre_sale(model::ABM, buyer::EconomicActor, seller::EconomicActor)
"""
function purchase!(model::ABM, buyer::EconomicActor, seller::EconomicActor, bp::Blueprint, units::Integer, pre_sales::Function...)
    available_units = 0
    price = get_price(model, seller, bp)

    if !isnothing(price)
        available_units = min(current_stock(seller.stock, bp), purchases_available(buyer.balance, price, units))

        if available_units > 0
            for pre_sale in pre_sales
                pre_sale(model, buyer, seller)
            end

            buyer.posessions[bp] = union!(buyer.posessions[bp], retrieve_stock!(seller.stock, bp, available_units))
            pay!(buyer.balance, seller.balance, price * available_units)
        end
    end

    return available_units
end

# Behavior functions

"""
    produce_stock!(actor::Actor)

Resupply stocks as needed.
"""
function produce_stock!(model::ABM, actor::EconomicActor)
    stock = actor.stock

    for producer in actor.producers
        p_bp = get_blueprint(producer)
        min_batches = 0
        max_batches = INF

        for bp in keys(p_bp.batch)
            batch = p_bp.batch[bp]

            min_units = max(min_stock(stock, bp) - current_stock(stock, bp), 0)
            min_batches = max(min_batches, Int(round(min_units / batch, RoundUp)))

            max_units = max(max_stock(stock, bp) - current_stock(stock, bp), 0)
            max_batches = min(max_batches, Int(round(max_units / batch, RoundDown)))
        end

        batches = max(min_batches, max_batches)

        for i in 1:batches
            products = produce!(producer, stock.stock)

            if !isempty(products)
                add_stock!(stock, products)
            else
                break
            end
        end
    end

    return actor
end
