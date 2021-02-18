abstract type Entity end

"""
    Entities
"""

struct Entities
    entities::Dict{Blueprint,Set{Entity}}
    Entities() = new(Dict{Blueprint,Set{Entity}}())
end

Base.isempty(entities::Entities) = isempty(entities.entities)
Base.empty(entities::Entities) = empty(entities.entities)
Base.empty!(entities::Entities) = empty!(entities.entities)
Base.keys(entities::Entities) = keys(entities.entities)
Base.values(entities::Entities) = values(entities.entities)
Base.getindex(entities::Entities, index::Blueprint) = index in keys(entities.entities) ? entities.entities[index] : Set{Entity}()
Base.setindex!(entities::Entities, e::Set{Entity}, index::Blueprint) = (entities.entities[index] = e)

function Base.push!(entities::Entities, entity::Entity)
    if entity.blueprint in keys(entities)
        push!(entities[entity.blueprint], entity)
    else
        entities[entity.blueprint] = Set{Entity}([entity])
    end

    return entities
end

function Base.push!(entities::Entities, units::Union{Vector{E}, Set{E}}) where {E <: Entity}
    for entity in units
        push!(entities, entity)
    end

    return entities
end

function Base.pop!(entities::Entities, bp::Blueprint)
    e = nothing

    if bp in keys(entities)
        if !isempty(entities[bp])
            e = pop!(entities[bp])
        end

        if isempty(entities[bp])
            pop!(entities.entities, bp)
        end
    end

    return e
end

function Base.delete!(entities::Entities, entity::Entity)
    bp = get_blueprint(entity)
    delete!(entities[bp], entity)

    if isempty(entities[bp])
        pop!(entities, bp)
    end

    return entities
end

"""
    num_entities(entities::Entities, bp::Blueprint)
"""
function num_entities(entities::Entities, bp::Blueprint)
    if bp in keys(entities)
        return length(entities[bp])
    else
        return 0
    end
end
