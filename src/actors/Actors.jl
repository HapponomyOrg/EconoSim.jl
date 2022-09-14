include("marginality.jl")
export Marginality, process

include("needs.jl")
export Needs, NeedType, Need
export want, usage
export push_usage!, push_want!, get_wants, get_usages, delete_usage!, delete_want!
export is_prioritised, usage_prioritised, wants_prioritised

include("actor.jl")
export Actor
export Prices
export has_type, add_type!, delete_type!
export has_behavior, add_behavior!, delete_bahavior!, clear_behaviors
export has_model_behavior, add_model_behavior!, delete_model_bahavior!, clear_model_behaviors
export push_producer!, delete_producer!, produce_stock!, purchase!
export get_price, set_price!
export get_posessions, get_stock, get_production_output
export actor_step!

include("marginal_actor.jl")
export make_marginal
export process_needs, process_usage, process_wants
