using UUIDs

mutable struct Consumable <: Entity
    id::UUID
    health::Health
    blueprint::ConsumableBlueprint
    Consumable(blueprint::ConsumableBlueprint) = new(uuid4(), Health(1), blueprint)
end

Base.show(io::IO, e::Consumable) = print(io, "Consumable(Name: $(get_name(e)), Health: $(health(e)), Blueprint: $(e.blueprint)))")

mutable struct Decayable <: Entity
    id::UUID
    health::Health
    blueprint::DecayableBlueprint
    Decayable(blueprint, health::Real = 1) = new(uuid4(), Health(health), blueprint)
end

Base.show(io::IO, e::Decayable) = print(io, "Decayable(Name: $(get_name(e)), Health: $(health(e)), Blueprint: $(e.blueprint)))")

mutable struct Product <: RestorableEntity
    id::UUID
    health::Health
    blueprint::ProductBlueprint
    uses::Int64
    destroyed::Bool
    Product(blueprint::ProductBlueprint, health::Real = 1) = new(uuid4(), Health(health), blueprint, 0, false)
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
mutable struct Producer <: RestorableEntity
    id::UUID
    health::Health
    blueprint::ProducerBlueprint
    uses::Int64
    destroyed::Bool
    Producer(
        blueprint::ProducerBlueprint,
        health::Real = 1
    ) = new(uuid4(), Health(health), blueprint, 0, false)
end

Base.show(io::IO, e::Producer) = print(
    io,
    "Producer(Name: $(get_name(e)), Health: $(health(e)), Blueprint: $(e.blueprint))",
)

ENTITY_CONSTRUCTORS = Dict(ConsumableBlueprint => Consumable, DecayableBlueprint => Decayable, ProductBlueprint => Product, ProducerBlueprint => Producer)



"""
    produce!

Produces batch based on the producer and the provided resouces. The maximum possible batch is generated. The uses resources are removed from the resources Dict and produced Entities are added to the products Dict.

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
    products = Entities()
    wastes = Entities()

    if usable(producer)
        if isempty(bp.batch_res) && isempty(bp.batch_tools)
            production_ready = true
        else
            result = extract!(resources, bp.batch_res, bp.batch_tools)
            production_ready = result[1]
            merge!(wastes, result[2])
        end

        if production_ready
            for prod_bp in keys(bp.batch)
                for j in 1:bp.batch[prod_bp]
                    push!(products, ENTITY_CONSTRUCTORS[typeof(prod_bp)](prod_bp))
                end
            end

            merge!(wastes, use!(producer))
        end
    end

    return merge!(products, wastes)
end
