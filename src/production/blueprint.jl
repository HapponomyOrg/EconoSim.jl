import Base: ==

using Base.Order
using UUIDs

nowaste() = Dict{Blueprint, Int64}()

type_id(blueprint::Blueprint) = blueprint.type_id

==(x::Blueprint, y::Blueprint) = type_id(x) == type_id(y)
Base.isless(x::Blueprint, y::Blueprint) = isless(type_id(x), type_id(y))

get_lifecycle(blueprint::Blueprint) = nothing
restorable(blueprint::Blueprint, health::Health) = restorable(get_lifecycle(blueprint), health)
restorable(blueprint::Blueprint) = restorable(blueprint, Health(1))
get_name(blueprint::Blueprint) = blueprint.name
get_maintenance_interval(blueprint::Blueprint) = get_maintenance_interval(get_lifecycle(blueprint))
maintenance_due(blueprint::Blueprint, uses::Integer) = maintenance_due(get_lifecycle(blueprint), uses)
maintenance!(blueprint::Blueprint, resources::Entities) = maintenance(get_lifecycle(blueprint), resources)
get_decay(blueprint::Blueprint) = Percentage(0)
decay!(blueprint::Blueprint, health::Health) = nowaste()
waste(blueprint::Blueprint) = blueprint.waste

function waste(blueprint::Blueprint, health::Health)
    return health == 0 && !restorable(blueprint, health) ? waste(blueprint) : nowaste()
end

function use!(blueprint::Blueprint, health::Health)
    wear!(get_lifecycle(blueprint), health)

    return waste(blueprint, health)
end

overuse!(blueprint::Blueprint, health::Health) = Entities()

function damage!(blueprint::Blueprint, health::Health, amount::Real)
    damage!(get_lifecycle(blueprint), health, amount)

    return waste(blueprint, health)
end

function destroy!(blueprint::Blueprint, health::Health)
    health.current = 0

    return waste(blueprint)
end

restore!(blueprint::Blueprint, health::Health, resources::Entities) = restore!(get_lifecycle(blueprint), health, resources)

maintain!(blueprint::Blueprint, resources::Entities) = maintain!(get_lifecycle(blueprint), resources)

struct ConsumableBlueprint <: Blueprint
    type_id::UUID
    name::String
    waste::Blueprints
    ConsumableBlueprint(
        name::String,
        waste::Blueprints = Dict{Blueprint, Int64}()
        ) = new(uuid4(), name, waste)
end

use!(blueprint::ConsumableBlueprint, health::Health) = destroy!(blueprint, health)

Base.show(io::IO, bp::ConsumableBlueprint) =
    print(io, "ConsumableBlueprint(Name: $(get_name(bp)))")

struct DecayableBlueprint <: Blueprint
    type_id::UUID
    name::String
    decay::Percentage
    waste::Blueprints
    DecayableBlueprint(
        name::String,
        decay::Real,
        waste::Blueprints = Dict{Blueprint, Int64}()
        ) = new(uuid4(), name, decay, waste)
end

Base.show(io::IO, bp::DecayableBlueprint) =
    print(io, "DecayableBlueprint(Name: $(get_name(bp)))")

decay!(blueprint::DecayableBlueprint, health::Health) = damage!(blueprint, health, value(health) * blueprint.decay)

use!(blueprint::DecayableBlueprint, health::Health) = decay!(blueprint, health)

get_lifecycle(blueprint::LifecycleBlueprint) = blueprint.lifecycle

function overuse!(blueprint::RestorableBlueprint, health::Health)
    overuse!(get_lifecycle(blueprint), health)

    return waste(blueprint, health)
end

struct ProductBlueprint <: RestorableBlueprint
    type_id::UUID
    name::String
    lifecycle::Restorable
    waste::Blueprints
    ProductBlueprint(
        name::String,
        lifecycle::Restorable = Restorable(),
        waste::Blueprints = Dict{Blueprint, Int64}()
        ) = new(uuid4(), name, lifecycle, waste)
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
struct ProducerBlueprint <: RestorableBlueprint
    type_id::UUID
    name::String
    lifecycle::Restorable
    batch_res::Blueprints
    batch_tools::Blueprints
    batch::Blueprints
    waste::Blueprints

    ProducerBlueprint(
        name::String,
        lifecycle::Restorable = Restorable();
        batch_res::Blueprints = Dict{Blueprint,Int64}(),
        batch_tools::Blueprints = Dict{Blueprint,Int64}(),
        batch::Blueprints = Dict{Blueprint,Int64}(),
        waste::Blueprints = Dict{Blueprint, Int64}()
    ) = new(uuid4(), name, lifecycle, batch_res, batch_tools, batch, waste)
end

Base.show(io::IO, bp::ProducerBlueprint) = print(
    io,
    "ProducerBlueprint(Name: $(get_name(bp)), $(bp.lifecycle), Batch resources: $(bp.batch_res), Batch tools: $(bp.batch_tools), Batch: $(bp.batch)")
