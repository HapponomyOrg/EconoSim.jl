using Agents

abstract type AbstractBalanceActor <: AbstractActor end

"""
    BalanceActor - agent representing an actor with a balance sheet.
"""
@agent struct BalanceActor{B}(Actor) <: AbstractBalanceActor
    balance::B
end

"""
    get_balance(actor::BalanceActor)
"""
get_balance(actor::AbstractBalanceActor) = actor.balance

function transfer_asset!(model::ABM,
                         source::AbstractBalanceActor,
                         destination::AbstractBalanceActor,
                         entry::BalanceEntry,
                         amount::Real)
    transfer_asset!(get_balance(source), get_balance(destination), entry, amount, timestamp = get_step(model))
end

function transfer_liability!(model::ABM,
                             source::AbstractBalanceActor,
                             destination::AbstractBalanceActor,
                             entry::BalanceEntry,
                             amount::Real)
    transfer_liability!(get_balance(source), get_balance(destination), entry, amount, timestamp = get_step(model))
end