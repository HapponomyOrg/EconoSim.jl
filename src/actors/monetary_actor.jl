using Agents

"""
MonetaryActor - agent representing an monetary actor.

# Fields
* id::Int - the id of the actor.
* types::Set{Symbol} - the types of the actor. Types are meant to be used in data collection and/or behavior functions.
* behaviors::Vector{Function} - the list of behavior functions which is called when the actor is activated.
* balance::Balance - the balance sheet of the actor.
* properties::Dict{Symbol, Any} - for internal use.

After creation, any field can be set on the actor, even those which are not part of the structure. This can come in handy when when specific state needs to be stored with the actor.
"""
mutable struct MonetaryActor <: AbstractActor
    id::Int64
    types::Set{Symbol}
    behaviors::Vector{Function}
    balance::AbstractBalance
    properties::D where {D <: Dict{Symbol, <:Any}}
end

"""
MonetaryActor - creation function for a generic actor.

# Parameters
* id::Int = ID_COUNTER - the id of the actor. When no id is given, the standard sequence of id's is used. Mixing the standard sequence and user defined id's is not advised.
* type::Union{Symbol, Nothing} = nothing - the types of the actor. Types are meant to be used in data collection and/or behavior functions.
* behavior::Union{Function, Nothing} = nothing - the default behavior function which is called when the actor is activated.
* balance::Balance = Balance() - the balance sheet of the actor.
"""
function MonetaryActor(id::Integer;
                        types::Union{Set{Symbol}, Symbol, Nothing} = nothing,
                        behaviors::Union{Vector{Function}, Function, Nothing} = nothing,
                        balance::AbstractBalance = Balance())
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

    actor = MonetaryActor(id,
                    typeset,
                    actor_behaviors,
                    balance,
                    Dict{Symbol, Any}())

    return actor
end