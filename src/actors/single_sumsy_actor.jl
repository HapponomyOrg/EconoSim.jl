using Agents

SINGLE_SUMSY = :single_sumsy

function make_single_sumsy!(sumsy::SuMSy,
                            actor::AbstractActor = MonetaryActor();
                            activate::Bool = true,
                            gi_eligible::Bool = true,
                            initialize::Bool = true,
                            contribution_settings::Union{SuMSy, Nothing} = nothing,
                            balance::SingleSuMSyBalance = SingleSuMSyBalance(sumsy,
                                                                                actor.balance,                                                                                
                                                                                activate = activate,
                                                                                gi_eligible = gi_eligible,
                                                                                initialize = initialize))
    actor.balance = balance
    add_type!(actor, SINGLE_SUMSY)
    actor.contribution_settings = contribution_settings
    actor.contribution = CUR_0

    return actor
end

set_sumsy_active!(actor::AbstractActor, flag::Bool) = set_sumsy_active!(actor.balance, flag)
is_sumsy_active(actor::AbstractActor) = is_sumsy_active(actor.balance)
set_gi_eligible!(actor::AbstractActor, flag::Bool) = set_gi_eligible(actor.blanace, flag)
is_gi_eligible(actor::AbstractActor) = is_gi_eligible(actor.balance)

set_contribution_settings(actor::AbstractActor, contribution_settings::Union{SuMSy, Nothing}) = (actor.contribution_settings = contribution_settings)
get_contribution_setting(actor::AbstractActor) = actor.contribution_settings
is_contribution_active(actor::AbstractActor) = !isnothing(actor.contribution_settings)
book_contribution!(actor::AbstractActor, amount::Real) = (actor.contribution += amount)
paid_contribution(actor::AbstractActor) = actor.contribution

sumsy_assets(actor::AbstractActor, step::Int = get_last_adjustment(actor.balance)) = sumsy_assets(actor.balance, timestamp = step)