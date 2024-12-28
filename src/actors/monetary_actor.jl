using Agents

"""
MonetaryActor - agent representing an actor that has a balance sheet.

# Fields
* balance::AbstractBalance - the balance sheet of the actor.

After creation, any field can be set on the actor, even those which are not part of the structure. This can come in handy when when specific state needs to be stored with the actor.
"""
@agent struct MonetaryActor{C}(Actor) <: BalanceActor{C}
    model::ABM
    balance::AbstractBalance = Balance()
    income::C
    expenses::C
end

function create_monetary_actor(model::ABM;
                                balance::AbstractBalance = Balance(),
                                income::Currency = CUR_0,
                                expenses::Currency = CUR_0,                           
                                types::Set{Symbol} = Set{Symbol}(),
                                behaviors::Vector{Function} = Vector{Function}())
    return MonetaryActor{Currency}(model,
                                    model = model,
                                    balance = balance,
                                    income = income,
                                    expenses = expenses,
                                    types = types,
                                    behaviors = behaviors)
end