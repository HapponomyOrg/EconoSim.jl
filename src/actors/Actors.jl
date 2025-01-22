include("marginality.jl")
export Marginality, process

include("needs.jl")
export Needs, NeedType, Need
export want, usage
export push_usage!, push_want!, get_wants, get_usages, delete_usage!, delete_want!
export is_prioritised, usage_prioritised, wants_prioritised

include("actor.jl")
export AbstractActor, Actor, create_actor
export has_type, add_type!, delete_type!
export has_behavior, add_behavior!, delete_bahavior!, clear_behaviors
export actor_step!

include("balance_actor.jl")
export BalanceActor
export get_balance, transfer_asset!, transfer_liability!

include("sumsy_actor.jl")
export SuMSyActor, create_sumsy_actor!
export set_sumsy_active!, is_sumsy_active, set_gi_eligible!, is_gi_eligible
export set_contribution_settings, get_contribution_settings, is_contribution_active, paid_contribution
export sumsy_assets


include("monetary_actor.jl")
export MonetaryActor, create_monetary_actor!

include("economic_actor.jl")
export EconomicAssets, Prices
export make_economic_actor!
export get_economic_assets, posessions, stock, producers, prices
export push_producer!, delete_producer!, produce_stock!, purchase!
export select_random_supplier
export get_price, set_price!
export get_posessions, get_stock, get_production_output

include("marginal_actor.jl")
export make_marginal!
export process_needs, process_usage, process_wants