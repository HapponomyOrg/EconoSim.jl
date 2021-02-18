import Base: ==

using Base.Order
using UUIDs
using DataStructures

@enum Direction up down

# Convenience aliases
ThresholdInput = Union{<: AbstractVector{<:Tuple{<:Real, <:Real}},
                <: AbstractSet{<:Tuple{<:Real, <:Real}}}
Thresholds = SortedSet{Tuple{Percentage, Float64}}

abstract type Lifecycle end
abstract type Blueprint end

reconstructable(lifecycle::Union{Lifecycle, Nothing}) = false
get_maintenance_interval(lifecycle::Union{Lifecycle, Nothing}) = INF

"""
    Restorable

Indicates a lifecycle with restorability, i.e. the entity can recover from damage.
Thresholds determine the multiplier for health at and below the threshold.

# Fields
- `damage_thresholds`: These are tuples, reverse ordered by percentage, holding damage multipliers. The applied multiplier corresponds with the lowest threshold which is higher than the health of the entity.
- `restoration_thresholds`: These are tuples, ordered by percentage, holding restoration multipliers. The applied multiplier corresponds with the lowest threshold which is higher than the health of the entity.
- `wear`: damage which occurs from each use. Succeptable to multipliers.

# Example
`
Restorable
    damage_thresholds = [(70.0%, 0.5), (100.0%, 0.2)]
    restoration_thresholds = [(40.0%, 0.0), (70.0%, 0.2), (100.0%, 0.3)]
`
When 1 damage is done it results in 0.2 damage actually being applied. Should health drop to 70% or less, then 0.5 damage would be applied. This indicates the robustness at various levels of damage.

When 1 damage is restored it results in 0.3 damage actually being restored. Should health drop to 40% or below no damage is being restored. This indicates restorability. The last tier indicates a level of damage beyond which no restoration is possible anymore.
"""
struct Restorable <: Lifecycle
    damage_thresholds::Thresholds
    restoration_thresholds::Thresholds
    restore_res::Dict{<:Blueprint,Int64}
    restore::Float64
    maintenance_interval::Int64
    maintenance_res::Dict{<:Blueprint,Int64}
    maintenance_tools::Dict{<:Blueprint,Int64}
    neglect_damage::Float64
    wear::Float64
    Restorable(;
        damage_thresholds::ThresholdInput=[(1, 1)],
        restoration_thresholds::ThresholdInput=[(1, 1)],
        restore_res::Dict{<:Blueprint,Int64} = Dict{Blueprint,Int64}(),
        restore::Real = 0,
        maintenance_interval::Integer = INF,
        maintenance_res::Dict{<:Blueprint,Int64} = Dict{Blueprint,Int64}(),
        maintenance_tools::Dict{<:Blueprint,Int64} = Dict{Blueprint,Int64}(),
        neglect_damage::Real = 0,
        wear::Real = 0) = new(
                    complete(damage_thresholds, down),
                    complete(restoration_thresholds, up),
                    restore_res,
                    restore,
                    maintenance_interval,
                    maintenance_res,
                    maintenance_tools,
                    neglect_damage,
                    wear)
end

"""
    complete

Make sure there are threshold where the percentage == 100% and 0%.
If the 100% threshold is added, use the same multiplier as the highest threshold.
If the 0% threshold is missing, add (0, 0). This means that, by default, destroyed entities can not be reconstructed.
If no threshold is present, add (0, 0) and (1, 1).
"""
function complete(thresholds::ThresholdInput, direction::Direction)
    thresholds = Thresholds(thresholds)

    if isempty(thresholds)
        push!(thresholds, (1, 1))
        push!(thresholds, (0, 0))
    elseif last(thresholds)[1] != 1
        push!(thresholds, (1, last(thresholds)[2]))
    elseif first(thresholds)[2] != 0
        push!(thresholds, (0, 0))
    end

    return thresholds
end

reconstructable(lifecycle::Restorable) = first(lifecycle.restoration_thresholds)[2] != 0
get_maintenance_interval(lifecycle::Restorable) = lifecycle.maintenance_interval

struct ConsumableBlueprint <: Blueprint
    type_id::UUID
    name::String
    ConsumableBlueprint(name::String) = new(uuid4(), name)
end

Base.show(io::IO, bp::ConsumableBlueprint) =
    print(io, "ConsumableBlueprint(Name: $(get_name(bp)))")

get_lifecycle(blueprint::ConsumableBlueprint) = nothing
reconstructable(blueprint::Blueprint) = reconstructable(get_lifecycle(blueprint))

struct DecayableBlueprint <: Blueprint
    type_id::UUID
    name::String
    decay::Percentage
    DecayableBlueprint(name::String, decay::Real) = new(uuid4(), name, decay)
end

Base.show(io::IO, bp::DecayableBlueprint) =
    print(io, "DecayableBlueprint(Name: $(get_name(bp)))")

get_lifecycle(blueprint::DecayableBlueprint) = nothing
get_decay(blueprint::DecayableBlueprint) = blueprint.decay

struct ProductBlueprint <: Blueprint
    type_id::UUID
    name::String
    lifecycle::Restorable
    ProductBlueprint(name::String,
        lifecycle::Restorable = Restorable()) = new(uuid4(), name, lifecycle)
end

Base.show(io::IO, bp::ProductBlueprint) =
    print(io, "ProductBlueprint(Name: $(get_name(bp)), $(bp.lifecycle))")

"""
    ProducerBlueprint

* type_id::UUID - the type id of the blueprint.
* name::String - blueprint name.
* lifecycle::Restorable - blueprint lifecycle
* batch_res::Dict{<:Blueprint,Int64} - the necessary resources for a production batch. These are destroyed during production.
* batch_tools::Dict{<:Blueprint,Int64} - the necessary tools for a production batch. These are used during production.
* batch::Dict{<:Blueprint,Int64} - output per batch.
"""
struct ProducerBlueprint <: Blueprint
    type_id::UUID
    name::String
    lifecycle::Restorable
    batch_res::Dict{<:Blueprint,Int64}
    batch_tools::Dict{<:Blueprint,Int64}
    batch::Dict{<:Blueprint,Int64}

    ProducerBlueprint(
        name::String,
        lifecycle::Restorable = Restorable();
        batch_res::Dict{<:Blueprint,Int64} = Dict{Blueprint,Int64}(),
        batch_tools::Dict{<:Blueprint,Int64} = Dict{Blueprint,Int64}(),
        batch::Dict{<:Blueprint,Int64} = Dict{Blueprint,Int64}()
    ) = new(uuid4(), name, lifecycle, batch_res, batch_tools, batch)
end

Base.show(io::IO, bp::ProducerBlueprint) = print(
    io,
    "ProducerBlueprint(Name: $(get_name(bp)), $(bp.lifecycle), Batch resources: $(bp.batch_res), Batch tools: $(bp.batch_tools), Batch: $(bp.batch)")

type_id(blueprint::Blueprint) = blueprint.type_id
get_name(blueprint::Blueprint) = blueprint.name
get_lifecycle(blueprint::Blueprint) = blueprint.lifecycle
get_maintenance_interval(blueprint::Blueprint) = get_maintenance_interval(get_lifecycle(blueprint))
get_decay(blueprint::Blueprint) = Percentage(0)

==(x::Blueprint, y::Blueprint) = type_id(x) == type_id(y)
Base.isless(x::Blueprint, y::Blueprint) = isless(type_id(x), type_id(y))
