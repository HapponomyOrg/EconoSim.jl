@agent struct SuMSyActor{C}(Actor) <: BalanceActor{C}
    model::ABM
    balance::SuMSyBalance
    income::C
    expenses::C
end

function create_sumsy_actor(model::ABM;
                            sumsy::SuMSy,
                            balance::SuMSyBalance = SingleSuMSyBalance(sumsy),
                            income::Currency = CUR_0,
                            expenses::Currency = CUR_0,
                            types::Set{Symbol} = Set{Symbol}(),
                            behaviors::Vector{Function} = Vector{Function}())                            
    return SuMSyActor{Currency}(model,
                                model = model,
                                balance = balance,
                                income = income,
                                expenses = expenses,
                                types = types,
                                behaviors = behaviors)
end

set_sumsy_active!(actor::SuMSyActor, flag::Bool) = set_sumsy_active!(actor.balance, flag)
set_sumsy_active!(actor::SuMSyActor, dep_entry::BalanceEntry, flag::Bool) = set_sumsy_active!(actor.balance, dep_entry, flag)
is_sumsy_active(actor::SuMSyActor) = is_sumsy_active(actor.balance)
is_sumsy_active(actor::SuMSyActor, dep_entry::BalanceEntry) = is_sumsy_active(actor.balance, dep_entry)
set_gi_eligible!(actor::SuMSyActor, flag::Bool) = set_gi_eligible!(actor.balance, flag)
is_gi_eligible(actor::SuMSyActor) = is_gi_eligible(actor.balance)

sumsy_assets(actor::SuMSyActor, step::Int = get_last_adjustment(actor.balance)) = sumsy_assets(actor.balance, timestamp = step)