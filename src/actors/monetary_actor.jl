using Agents

"""
MonetaryActor - agent representing an actor that has a balance sheet.

# Fields
* balance::AbstractBalance - the balance sheet of the actor.

After creation, any field can be set on the actor, even those which are not part of the structure.
This can come in handy when when specific state needs to be stored with the actor.
"""
@agent struct MonetaryActor{C}(Actor) <: BalanceActor{C}
    model::ABM
    balance::AbstractBalance = Balance()
    income::C
    expenses::C
end

function create_monetary_actor(model::ABM;
                                allow_negative_assets::Bool = false,
                                allow_negative_liabilities::Bool = false,
                                balance::AbstractBalance = Balance(def_min_asset = allow_negative_assets ? typemin(Currency) : CUR_0,
                                                                  def_min_liability = allow_negative_liabilities ? typemin(Currency) : CUR_0),
                                income::Real = 0,
                                expenses::Real = 0,                           
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