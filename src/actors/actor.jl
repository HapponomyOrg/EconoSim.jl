using Agents

abstract type AbstractActor <: AbstractAgent end

"""
Actor - generic agent representing an actor.

# Fields
* types::Set{Symbol} - the types of the actor. Types are meant to be used in data collection and/or behavior functions.
* behaviors::Vector{Function} - the list of behavior functions which is called when the actor is activated.
* properties::Dict{Symbol, Any} - for internal use.
"""
@agent struct Actor(NoSpaceAgent) <: AbstractActor
    types::Set{Symbol} = Set{Symbol}()
    behaviors::Vector{Function} = Vector{Function}()
    properties::D where {D <: Dict{Symbol, <:Any}} = Dict{Symbol, Any}()
end

function Base.getproperty(actor::AbstractActor, s::Symbol)
    properties = getfield(actor, :properties)

    if s in keys(properties)
        return properties[s]
    elseif s in fieldnames(typeof(actor))
        return getfield(actor, s)
    else
        return nothing
    end
end

function Base.setproperty!(actor::AbstractActor, s::Symbol, value)
    if s in fieldnames(typeof(actor))
        setfield!(actor, s, value)
    else
        actor.properties[s] = value
    end

    return value
end

function Base.hasproperty(actor::AbstractActor, s::Symbol)
    return s in fieldnames(Actor) || s in keys(actor.properties)
end

add_type!(actor::AbstractActor, type::Symbol) = (push!(actor.types, type); actor)
delete_type!(actor::AbstractActor, type::Symbol) = (delete!(actor.types, type); actor)
has_type(actor::AbstractActor, type::Symbol) = type in actor.types

has_behavior(actor::AbstractActor, behavior::Function) = behavior in actor.behaviors
add_behavior!(actor::AbstractActor, behavior::Function) = (push!(actor.behaviors, behavior); actor)
delete_behavior!(actor::AbstractActor, behavior::Function) = (delete_element!(actor.behaviors, behavior); actor)
clear_behaviors(actor::AbstractActor) = (empty!(actor.behaviors); actor)

function actor_step!(actor::AbstractActor, model::ABM)
    for behavior in actor.behaviors
        behavior(model, actor)
    end
end

"""
    get_balance(actor::AbstractActor)

All subtypes of Actor must have a balance field.
"""
get_balance(actor::AbstractActor) = actor.balance