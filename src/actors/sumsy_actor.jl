@agent struct SuMSyActor{C}(Actor) <: BalanceActor{C}
    model::ABM
    balance::SuMSyBalance
    contribution_settings::Union{SuMSy, Nothing}
    contribution::C = CUR_0
end

function create_sumsy_actor(model::ABM;
                            balance::SuMSyBalance = SingleSuMSyBalance(model.sumsy),
                            contribution_settings::Union{SuMSy, Nothing} = nothing,
                            contribution::Real = CUR_0,
                            types::Set{Symbol} = Set{Symbol}(),
                            behaviors::Vector{Function} = Vector{Function}())                            
    return SuMSyActor{Currency}(model,
                                model = model,
                                balance = balance,
                                contribution_settings = contribution_settings,
                                contribution = contribution,
                                types = types,
                                behaviors = behaviors)
end

set_sumsy_active!(actor::SuMSyActor, flag::Bool) = set_sumsy_active!(actor.balance, flag)
is_sumsy_active(actor::SuMSyActor) = is_sumsy_active(actor.balance)
set_gi_eligible!(actor::SuMSyActor, flag::Bool) = set_gi_eligible(actor.balance, flag)
is_gi_eligible(actor::SuMSyActor) = is_gi_eligible(actor.balance)

set_contribution_settings(actor::SuMSyActor, contribution_settings::Union{SuMSy, Nothing}) = (actor.contribution_settings = contribution_settings)
get_contribution_setting(actor::SuMSyActor) = actor.contribution_settings
is_contribution_active(actor::SuMSyActor) = !isnothing(actor.contribution_settings)
book_contribution!(actor::SuMSyActor, amount::Real) = (actor.contribution += amount)
paid_contribution(actor::SuMSyActor) = actor.contribution

sumsy_assets(actor::SuMSyActor, step::Int = get_last_adjustment(actor.balance)) = sumsy_assets(actor.balance, timestamp = step)