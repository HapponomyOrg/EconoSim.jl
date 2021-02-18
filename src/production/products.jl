
using UUIDs

# TODO move damage functions to LifeCycle.
# damage!(product, damage) = damage!(lifecycle, health, damage)
abstract type Enhancer <: Entity end

==(x::Entity, y::Entity) = x.id == y.id

get_blueprint(entity::Entity) = entity.blueprint
type_id(entity::Entity) = type_id(get_blueprint(entity))
is_type(entity::Entity, blueprint::Blueprint) = type_id(entity) == type_id(blueprint)
get_name(entity::Entity) = get_name(get_blueprint(entity))
get_lifecycle(entity::Entity) = get_lifecycle(get_blueprint(entity))
get_maintenance_interval(entity::Entity) = get_maintenance_interval(get_blueprint(entity))
id(entity::Entity) = entity.id

mutable struct Consumable <: Entity
    id::UUID
    used::Bool
    blueprint::ConsumableBlueprint
    Consumable(blueprint::ConsumableBlueprint, used::Bool = false) = new(uuid4(), used, blueprint)
end

Base.show(io::IO, e::Consumable) = print(io, "Consumable(Name: $(get_name(e)), Health: $(health(e)), Blueprint: $(e.blueprint)))")

health(consumable::Consumable) = consumable.used ? Health(0) : Health(1)
use!(consumable::Consumable) = (consumable.used = true; consumable)
restore!(consumable::Consumable, resources::Entities = Entities()) = consumable
maintenance_due(consumable::Consumable) = false
maintain!(consumable::Consumable, resources::Entities = Entities()) = false
damage!(consumable::Consumable, damage::Real = 1) = damage == 0 ? consumable : use!(consumable)
destroy!(consumable::Consumable) = (consumable.used = true; consumable)

mutable struct Decayable <: Entity
    id::UUID
    health::Health
    blueprint::DecayableBlueprint
    Decayable(blueprint, health::Real = 1) = new(uuid4(), Health(health), blueprint)
end

Base.show(io::IO, e::Decayable) = print(io, "Decayable(Name: $(get_name(e)), Health: $(health(e)), Blueprint: $(e.blueprint)))")

use!(decayable::Decayable) = decay!(decayable)
restore!(decayable::Decayable, resources::Entities = Entities()) = decayable
maintenance_due(decayable) = false
maintain!(decayable::Decayable, resources::Entities = Entities()) = false
damage!(decayable::Decayable, damage::Real = 1) = decayable
decay!(decayable::Decayable) = (decayable.health -= decayable.health * get_decay(get_blueprint(decayable)); decayable)

mutable struct Product <: Entity
    id::UUID
    health::Health
    blueprint::ProductBlueprint
    used::Int64
    Product(blueprint::ProductBlueprint, health::Real = 1) = new(uuid4(), Health(health), blueprint, 0)
end

Base.show(io::IO, e::Product) = print(io, "Product(Name: $(get_name(e)), Health: $(health(e)), Blueprint: $(e.blueprint)))")

"""
    Producer

An Entity with the capability to produce other Entities.

# Fields
- `id`: The id of the Producer.
- `lifecycle`: The lifecycle of the Producer.
- `blueprint`: The blueprint the producer is based on.
"""
mutable struct Producer <: Entity
    id::UUID
    health::Health
    blueprint::ProducerBlueprint
    used::Int64
    Producer(
        blueprint::ProducerBlueprint,
        health::Real = 1
    ) = new(uuid4(), Health(health), blueprint, 0)
end

Base.show(io::IO, e::Producer) = print(
    io,
    "Producer(Name: $(get_name(e)), Health: $(health(e)), Blueprint: $(e.blueprint))",
)

health(entity::Entity) = entity.health

ENTITY_CONSTRUCTORS = Dict(ConsumableBlueprint => Consumable, DecayableBlueprint => Decayable, ProductBlueprint => Product, ProducerBlueprint => Producer)

function extract!(source::Entities, resource_req::Dict{B1,Int64}, tool_req::Dict{B2,Int64} = Dict{B2,Int64}()) where {B1 <: Blueprint, B2 <: Blueprint}
    resources = Set()
    tools = Set()
    extracted = true

    for t in ((resource_req, resources), (tool_req, tools))
        requirements = t[1]
        store = t[2]

        if extracted && !isempty(requirements)
            for bp in keys(requirements)
                if bp in keys(source) && length(source[bp]) >= requirements[bp]
                    union!(store, extract(source[bp], requirements[bp], usable))
                else
                    extracted = false
                end
            end
        end
    end

    if extracted
        for todo in ((resources, destroy!), (tools, use!))
            targets = todo[1]
            action = todo[2]

            for entity in targets
                action(entity)

                if !usable(entity) && !reconstructable(entity)
                    delete!(source, entity)
                end
            end
        end
    end

    return extracted
end

"""
    produce!

Produces batch based on the producer and the provided resouces. The maximum possible batch is generated. The used resources are removed from the resources Dict and produced Entities are added to the products Dict.

# Returns
A named tuple {products::Entities, resources::Entities, batches::Int64} where
* products = produced entities
* resources = leftover resources
* batches = number of produced batches
"""
function produce!(producer::Producer,
                resources::Entities = Entities())
    bp = get_blueprint(producer)
    batches = 0
    products = Set{Entity}()

    if health(producer) > 0
        if isempty(bp.batch_res) && isempty(bp.batch_tools)
            production_ready = true
        else
            production_ready = extract!(resources, bp.batch_res, bp.batch_tools)
        end

        if production_ready
            for prod_bp in keys(bp.batch)
                for j in 1:bp.batch[prod_bp]
                    push!(products, ENTITY_CONSTRUCTORS[typeof(prod_bp)](prod_bp))
                end
            end

            use!(producer)
        end
    end

    return products
end

function change_health!(entity::Entity, change::Real, direction::Direction)
    lifecycle = get_lifecycle(entity)
    surplus_change = nothing

    if direction == up
        thresholds = collect(lifecycle.restoration_thresholds)
    else
        thresholds = collect(lifecycle.damage_thresholds)
    end

    if (health(entity) == 1 && direction == up) ||
        (health(entity) == 0 && direction == down)
        # Health can go no higher than 100% or lower than 0%
        return entity
    elseif length(thresholds) == 2
        # It's easy when there are only the 0% and 100% thresholds
        if direction == up && health(entity) == 0
            real_change = thresholds[1][2] * change
        else
            real_change = thresholds[2][2] * change
        end

        surplus_change = nothing
    else
        multiplier = nothing
        max_change = nothing
        previous = nothing
        before_previous = nothing

        if health(entity) == 1 && direction == down
            multiplier = thresholds[end][2]
            max_change = thresholds[end][1] - thresholds[end - 1][1]
        elseif health(entity) == 0 && direction == up
            multiplier = first(thresholds)[2]
            max_change = thresholds[2][1] - thresholds[1][1]
        else
            for threshold in thresholds
                if health(entity) < threshold[1]
                    multiplier = threshold[2]

                    if direction == up && threshold != last(thresholds)
                        max_change = threshold[1] - value(health(entity))
                    elseif direction == down && previous != nothing
                        if health(entity) != previous[1]
                            max_change = value(health(entity)) - previous[1]
                        else
                            multiplier = previous[2]

                            if before_previous != nothing
                                max_change = value(health(entity)) - before_previous[1]
                            end
                        end
                    end
                end

                if multiplier != nothing
                    break
                end

                before_previous = previous
                previous = threshold
            end
        end

        real_change = change * multiplier

        if max_change != nothing && real_change > max_change
            surplus_change = (real_change - max_change) / multiplier
            real_change = max_change
        end
    end

    if direction == up
        entity.health += real_change
    else
        entity.health -= real_change
    end

    return change_health!(entity, surplus_change, direction)
end

function change_health!(entity::Entity, change::Nothing, direction::Direction)
    return entity
end

function use!(entity::Entity)
    lifecycle = get_lifecycle(entity)
    change_health!(entity, lifecycle.wear, down)
    entity.used += 1

    if entity.used > lifecycle.maintenance_interval
        change_health!(entity, lifecycle.neglect_damage, down)
    end

    return entity
end

"""
Restores damage according to the restoration thresholds.
"""
function restore!(entity::Entity, resources::Entities = Entities())
    lifecycle = get_lifecycle(entity)

    if isempty(lifecycle.restore_res) || extract!(lifecycle.restore_res, resources)
        change_health!(entity, lifecycle.restore, up)
    end

    return entity
end

maintenance_due(entity::Entity) = entity.used >= get_maintenance_interval(entity)

function maintain!(entity::Entity, resources::Entities = Entities())
    lifecycle = get_lifecycle(entity)

    if (isempty(lifecycle.maintenance_res) && isempty(lifecycle.maintenance_tools)) || extract!(resources, lifecycle.maintenance_res, lifecycle.maintenance_tools)
        entity.used = 0
        return true
    else
        return false
    end
end

damage!(entity::Entity, damage::Real) = change_health!(entity, damage, down)
decay!(entity::Entity) = entity
destroy!(entity::Entity) = (entity.health = Health(0); entity)
usable(entity::Entity) = health(entity) != 0
reconstructable(entity::Entity) = reconstructable(get_lifecycle(entity))
damaged(entity::Entity) = health(entity) < 1
