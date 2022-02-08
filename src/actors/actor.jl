using Agents

global ID_COUNTER = 0

"""
    Actor - agent representing an economic actor.

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
mutable struct Actor <: AbstractAgent
    id::Int64
    types::Set{Symbol}
    behaviors::Vector{Function}
    balance::Balance
    posessions::Entities
    stock::Stock
    producers::Set{Producer}
    prices::Dict{Blueprint, Price}
    properties::D where {D <: Dict{Symbol, <:Any}}
end

"""
    Actor - creation function for a generic actor.

# Parameters
* id::Int = ID_COUNTER - the id of the actor. When no id is given, the standard sequence of id's is used. Mixing the standard sequence and user defined id's is not advised.
* type::Union{Symbol, Nothing} = nothing - the types of the actor. Types are meant to be used in data collection and/or behavior functions.
* behavior::Union{Function, Nothing} = nothing - the default behavior function which is called when the actor is activated.
* balance::Balance = Balance() - the balance sheet of the actor.
* posessions::Entities = Entities() - the entities in personal posession of the actor.
* stock::Stock = Stock() - the stock held by the actor. The stock is considered to be used for business purposes.
* producers::Union{AbstractVector{Producer}, AbstractSet{Producer}} = Set{Producer}() - the production facilities of the actor.
"""
function Actor(;id::Integer = ID_COUNTER,
        types::Union{Set{Symbol}, Symbol, Nothing} = nothing,
        behavior::Union{Function, Nothing} = nothing,
        balance::Balance = Balance(),
        posessions::Entities = Entities(),
        stock::Stock = Stock(),
        producers::Union{AbstractVector{Producer}, AbstractSet{Producer}} = Set{Producer}(),
        prices::D = Dict{Blueprint, Price}()) where {D <: Dict{<: Blueprint, Price}}
    if isnothing(types)
        typeset = Set{Symbol}()
    elseif types isa Symbol
        typeset = Set([types])
    else
        typeset = types
    end

    behaviors = isnothing(behavior) ? Vector{Function}() : Vector([behavior])
    global ID_COUNTER += 1

    actor = Actor(id, typeset, behaviors, balance, posessions, stock, Set(producers), prices, Dict{Symbol, Any}())

    return actor
end

function Base.getproperty(actor::Actor, s::Symbol)
    properties = getfield(actor, :properties)

    if s in keys(properties)
        return properties[s]
    elseif s in fieldnames(Actor)
        return getfield(actor, s)
    else
        return nothing
    end
end

function Base.setproperty!(actor::Actor, s::Symbol, value)
    if s in fieldnames(Actor)
        setfield!(actor, s, value)
    else
        actor.properties[s] = value
    end

    return value
end

function Base.hasproperty(actor::Actor, s::Symbol)
    return s in fieldnames(Actor) || s in keys(actor.properties)
end

add_type!(actor::Actor, type::Symbol) = (push!(actor.types, type); actor)
delete_type!(actor::Actor, type::Symbol) = (delete!(actor.types, type); actor)
has_type(actor::Actor, type::Symbol) = type in actor.types

has_behavior(actor::Actor, behavior::Function) = behavior in actor.behaviors
add_behavior!(actor::Actor, behavior::Function) = (push!(actor.behaviors, behavior); actor)
delete_behavior!(actor::Actor, behavior::Function) = (delete_element!(actor.behaviors, behavior); actor)
clear_behaviors(actor::Actor) = (empty!(actor.behaviors); actor)

push_producer!(actor::Actor, producer::Producer) = (push!(actor.producers, producer); actor)
delete_producer!(actor::Actor, producer::Producer) = (delete!(actor.producers, producer); actor)

get_posessions(actor::Actor, bp::Blueprint) = bp in keys(actor.posessions) ? length(actor.posessions[bp]) : 0
get_stock(actor::Actor, bp::Blueprint) = current_stock(actor.stock, bp)

"""
    get_production_output(actor::Actor)

Get the set of all blueprints produced by the actor.
"""
function get_production_output(actor::Actor)
    production = Set{Blueprint}()

    for producer in keys(actor.producers)
        production = union(Set(keys(get_blueprint(producer).batch)), production)
    end

    return production
end

set_price!(actor::Actor, bp::Blueprint, price::Price) = (actor.prices[bp] = price; actor)
get_price(actor::Actor, bp::Blueprint) = haskey(actor.prices, bp) ? actor.prices[bp] : nothing
get_price(model, actor::Actor, bp::Blueprint) = isnothing(get_price(actor, bp)) ? get_price(model, bp) : get_price(actor, bp)

function purchase!(model, buyer::Actor, seller::Actor, bp::Blueprint, units::Integer)
    price = get_price(model, seller, bp)

    if isnothing(price)
        units = 0
    else
        units = min(current_stock(seller.stock, bp), purchases_available(buyer.balance, price, units))

        if units > 0
            buyer.posessions[bp] = union!(buyer.posessions[bp], retrieve_stock!(seller.stock, bp, units))
            pay!(buyer.balance, seller.balance, price * units, model.step, comment = bp.name)
        end
    end

    return units
end

function actor_step!(actor, model)
    for behavior in actor.behaviors
        behavior(model, actor)
    end
end

# Behavior functions

"""
    produce_stock!(actor::Actor)

Resupply stocks as needed.
"""
function produce_stock!(model, actor::Actor)
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
