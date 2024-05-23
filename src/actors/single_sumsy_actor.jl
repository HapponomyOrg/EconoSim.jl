using Agents

SINGLE_SUMSY = :single_sumsy

"""
    SingleSuMSyActor - agent representing an actor with a single SuMSy balance sheet.
"""
@agent struct SingleSuMSyActor(Actor) <: BalanceActor
    model::ABM
    balance::SingleSuMSyBalance
    contribution_settings::Union{SuMSy, Nothing}
    contribution::Real = CUR_0
end

set_sumsy_active!(actor::SingleSuMSyActor, flag::Bool) = set_sumsy_active!(actor.balance, flag)
is_sumsy_active(actor::SingleSuMSyActor) = is_sumsy_active(actor.balance)
set_gi_eligible!(actor::SingleSuMSyActor, flag::Bool) = set_gi_eligible(actor.balance, flag)
is_gi_eligible(actor::SingleSuMSyActor) = is_gi_eligible(actor.balance)

set_contribution_settings(actor::SingleSuMSyActor, contribution_settings::Union{SuMSy, Nothing}) = (actor.contribution_settings = contribution_settings)
get_contribution_setting(actor::SingleSuMSyActor) = actor.contribution_settings
is_contribution_active(actor::SingleSuMSyActor) = !isnothing(actor.contribution_settings)
book_contribution!(actor::SingleSuMSyActor, amount::Real) = (actor.contribution += amount)
paid_contribution(actor::SingleSuMSyActor) = actor.contribution

sumsy_assets(actor::SingleSuMSyActor, step::Int = get_last_adjustment(actor.balance)) = sumsy_assets(actor.balance, timestamp = step)