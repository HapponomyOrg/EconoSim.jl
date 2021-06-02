==(x::Entity, y::Entity) = x.id == y.id

id(entity::Entity) = entity.id
health(entity::Entity) = entity.health
get_blueprint(entity::Entity) = entity.blueprint
type_id(entity::Entity) = type_id(get_blueprint(entity))
is_type(entity::Entity, blueprint::Blueprint) = type_id(entity) == type_id(blueprint)
get_name(entity::Entity) = get_name(get_blueprint(entity))
get_lifecycle(entity::Entity) = get_lifecycle(get_blueprint(entity))
restorable(entity::Entity) = restorable(get_lifecycle(entity))

use!(entity::Entity) = (entity.health -= wear(get_blueprint(entity)); entity)

function damage!(entity::Entity, amount::Real)
    entity.health -= damage(get_blueprint(entity), damage)

    return entity
end

damaged(entity::Entity) = health(entity) < 1

function restore!(entity::Entity, resources::Entities = Entities())
    entity.health += restore(get_blueprint(entity), resources)

    return entity
end

maintenance_due(entity::Entity) = false
get_maintenance_interval(entity::Entity) = get_maintenance_interval(get_blueprint(entity))

function maintain!(entity::Entity, resources::Entities = Entities())
    entity.health += maintenance(get_blueprint(entity), resources)

    return entity
end

function destroy!(entity::Entity)
    entity.health = 0
    wastes = Entities()
    waste_bps = waste(get_blueprint(entity))

    for bp in keys(waste_bps)
        for x in 1:waste_bps[bp]
            push!(wastes, ENTITY_CONSTRUCTORS[typeof(bp)](bp))
        end
    end

    return wastes
end

destroyed(entity::Entity) = entity.health == 0
usable(entity::Entity) = !destroyed(entity)
