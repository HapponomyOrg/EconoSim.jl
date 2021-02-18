using DataStructures
using Random

"""
    Needs - indicates the needs of an Actor.

* usage_priorities::Set{Int64} - the set of usage priorities. If this contains less than 2 elements, usage is randomised.
* wants_priorities::Set{Int64} -  the set of wants priorities. If this contains less than 2 elements, purchasing wants is randomised.
* use::Dict{Tuple{Int64, Blueprint}, Marginality} - indicates what the actor will use each cycle. The Int64 in the key tuple indicates priority.
* wants::Dict{Tuple{Int64, Blueprint}, Marginality} - indicates what the actor will try to purchase each cycle.
"""
struct Needs
    usage_priorities::Set{Int64}
    wants_priorities::Set{Int64}
    usage::SortedDict{Tuple{Int64, Blueprint}, Marginality}
    wants::SortedDict{Tuple{Int64, Blueprint}, Marginality}

    Needs() = new(Set{Int64}(), Set{Int64}(), SortedDict{Tuple{Int64, Blueprint}, Marginality}(), SortedDict{Tuple{Int64, Blueprint}, Marginality}())
end

@enum NeedType usage want

function needs_data(needs::Needs, type::NeedType)
    if type == usage
        priorities = needs.usage_priorities
        target = needs.usage
    else
        priorities = needs.wants_priorities
        target = needs.wants
    end

    return (target = target, priorities = priorities)
end

Need = @NamedTuple{blueprint::B, units::Integer} where {B <: Blueprint}

"""
    push!(needs::Needs,
            type::NeedType,
            bp::Blueprint,
            marginality::Marginality,
            priority::Integer = 0)

Adds a usage or want to the needs.

* type::NeedType - usage or want
* bp::B
* marginality::Marginality
* priority::Integer - default is 0.
"""
function Base.push!(needs::Needs,
                type::NeedType,
                bp::Blueprint,
                marginality::Marginality;
                priority::Integer = 0)
    data = needs_data(needs, type)

    push!(data.priorities, priority)
    data.target[(priority, bp)] = marginality

    return needs
end

function push_usage!(needs::Needs,
                    bp::Blueprint,
                    marginality::Marginality;
                    priority::Integer = 0)
    return push!(needs, usage, bp, marginality, priority = priority)
end

push_usage!(needs::Needs, bp::Blueprint, marginality::Vector{<:Tuple{Integer, Real}}; priority::Integer = 0) = push_usage!(needs, bp, Marginality(marginality), priority = priority)

function push_want!(needs::Needs,
                    bp::Blueprint,
                    marginality::Marginality;
                    priority::Integer = 0)
    return push!(needs, want, bp, marginality, priority = priority)
end

push_want!(needs::Needs, bp::Blueprint, marginality::Vector{<:Tuple{Integer, Real}}; priority::Integer = 0) = push_want!(needs, bp, Marginality(marginality), priority = priority)

function Base.delete!(needs::Needs,
                    type::NeedType,
                    bp::Blueprint;
                    priority::Integer = nothing)
    data = needs_data(needs, type)

    if priority == nothing
        # Delete all priorities
        for key in keys(target.data)
            if key[2] == bp
                delete!(target.data, key)
            end
        end
    else
        delete!(target.data, (priority, bp))
    end

    # Reconstruct priorities set
    empty!(target.priorities)

    for key in keys(target.data)
        push!(target.priorities, key[1])
    end

    return needs
end

function delete_usage!(needs::Needs,
                    bp::Blueprint;
                    priority::Integer = nothing)
    return delete!(needs, usage, bp, priority = priority)
end

function delete_want!(needs::Needs,
                    bp::Blueprint;
                    priority::Integer = nothing)
    return delete!(needs, want, bp, priority = priority)
end

is_prioritised(needs::Needs, type::NeedType) = length(needs_data(needs, type).priorities) > 1
usage_prioritised(needs) = is_prioritised(needs, usage)
wants_prioritised(needs) = is_prioritised(needs, wants)


"""
    process_needs(needs::Needs
                type::NeedType,
                posessions::Entities = Entities())

Get a vector of all the needs of the actor of the specified need type. The vector contains named tuples {blueprint::Blueprint, units::Int}. If the need type is prioritised the list is in order of priority, otherwise it is randomized.
"""
function process_needs(needs::Needs,
                    type::NeedType,
                    posessions::Entities = Entities())
    result = Vector{@NamedTuple{blueprint::Blueprint, units::Int64}}()
    data = needs_data(needs, type)

    for key in keys(data.target)
        if type == want
            units = num_entities(posessions, key[2])
        else
            units = 0
        end

        units = process(data.target[key], units)
        push!(result, (blueprint = key[2], units = units))
    end

    if !is_prioritised(needs, type)
        Random.shuffle!(result)
    end

    return result
end

"""
    process_usage(needs::Needs)

Determine the items the actor wants to use. This in independant on the actual items in posession of the actor.
"""
process_usage(needs::Needs) = process_needs(needs, usage)

"""
    process_wants(needs::Needs, posessions = Entities())

Determine the items the actor wants, base on the items in posession of the actor.
"""
process_wants(needs::Needs, posessions = Entities()) = process_needs(needs, want, posessions)
