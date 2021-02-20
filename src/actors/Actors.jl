include("marginality.jl")
export Marginality, process

include("needs.jl")
export Needs, NeedType
export want, usage
export push_usage!, push_want!, delete_usage!, delete_want!
export is_prioritised, usage_prioritised, wants_prioritised

include("actor.jl")
export Actor
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

include("model.jl")
export create_econo_model, econo_step!, econo_model_step!
export get_step, get_price, set_price!
