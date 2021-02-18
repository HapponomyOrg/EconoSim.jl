include("blueprint.jl")
export Direction, down, up, Thresholds
export Lifecycle, Restorable
export Blueprint, ConsumableBlueprint, DecayableBlueprint, ProductBlueprint, ProducerBlueprint
export type_id, get_name, get_lifecycle, get_maintenance_interval

include("entities.jl")
export Entities, Entity
export num_entities

include("stock.jl")
export Stock
export current_stock, has_stock, stocked, overstocked, add_stock!, retrieve_stock!, min_stock, min_stock!, max_stock, max_stock!, stock_limits, stock_limits!, purge!

include("products.jl")
export Enhancer, Consumable, Decayable, Product, Producer
export id, get_blueprint, is_type, produce!
export health, damaged, usable, reconstructable, use!, restore!, maintenance_due, maintain!, damage!, decay!, destroy!
