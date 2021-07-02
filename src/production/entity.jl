==(x::Entity, y::Entity) = x.id == y.id

id(entity::Entity) = entity.id
health(entity::Entity) = entity.health
get_blueprint(entity::Entity) = entity.blueprint
type_id(entity::Entity) = type_id(get_blueprint(entity))
is_type(entity::Entity, blueprint::Blueprint) = type_id(entity) == type_id(blueprint)
get_name(entity::Entity) = get_name(get_blueprint(entity))
get_lifecycle(entity::Entity) = get_lifecycle(get_blueprint(entity))
restorable(entity::Entity) = restorable(get_blueprint(entity), health(entity))

function use!(entity::Entity)
    return produce_waste(use!(get_blueprint(entity), health(entity)))
end

function use!(entity::RestorableEntity)
    wastes = invoke(use!, Tuple{Entity}, entity)

    entity.uses += 1

    if entity.uses > get_maintenance_interval(entity::Entity)
        return merge!(wastes, produce_waste(overuse!(get_blueprint(entity), health(entity))))
    else
        return wastes
    end
end

function damage!(entity::Entity, amount::Real)
    return produce_waste(damage!(get_blueprint(entity), health(entity), amount))
end

damaged(entity::Entity) = health(entity) < 1

decay!(entity::Entity) = decay!(get_blueprint(entity), health(entity))

restore!(entity::Entity, resources::Entities = Entities()) = restore!(get_blueprint(entity), health(entity), resources)

maintenance_due(entity::Entity) = false
maintenance_due(entity::RestorableEntity) = entity.uses >= get_maintenance_interval(entity::Entity)
get_maintenance_interval(entity::Entity) = get_maintenance_interval(get_blueprint(entity))

function maintain!(entity::Entity, resources::Entities = Entities())
    result = maintain!(get_blueprint(entity), resources)

    if result[1]
        entity.uses = 0
    end

    return result
end

function destroy!(entity::Entity)
    return produce_waste(destroy!(get_blueprint(entity), health(entity)))
end

function destroy!(entity::RestorableEntity)
    entity.destroyed = true

    return invoke(destroy!, Tuple{Entity}, entity)
end

destroyed(entity::Entity) = entity.health == 0
destroyed(entity::RestorableEntity) = entity.destroyed || !restorable(entity)

usable(entity::Entity) = !destroyed(entity)

function produce_waste(waste_bps::Blueprints)
    wastes = Entities()

    for bp in keys(waste_bps)
        for x in 1:waste_bps[bp]
            push!(wastes, ENTITY_CONSTRUCTORS[typeof(bp)](bp))
        end
    end

    return wastes
end


# Old functions


#
# """
# Restores damage according to the restoration thresholds.
# """
# function restore!(entity::Entity, resources::Entities = Entities())
#     lifecycle = get_lifecycle(entity)
#
#     if isempty(lifecycle.restore_res) || extract!(lifecycle.restore_res, resources)
#         change_health!(entity, lifecycle.restore, up)
#     end
#
#     return entity
# end
#
#
# maintenance_due(entity::Entity) = entity.uses >= get_maintenance_interval(entity)
#
# function maintain!(entity::Entity, resources::Entities = Entities())
#     lifecycle = get_lifecycle(entity)
#
#     if (isempty(lifecycle.maintenance_res) && isempty(lifecycle.maintenance_tools)) || extract!(resources, lifecycle.maintenance_res, lifecycle.maintenance_tools)
#         entity.uses = 0
#         return true
#     else
#         return false
#     end
# end
