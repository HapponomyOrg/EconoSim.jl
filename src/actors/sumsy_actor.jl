@agent struct SuMSyActor{C, B}(Actor) <: BalanceActor{C}
    model::ABM
    balance::B
    income::C
    expenses::C
end

function create_sumsy_actor(model::ABM;
                            sumsy::SuMSy,
                            sumsy_interval::Int = 30,
                            allow_negatives::Bool = false,
                            balance::SuMSyBalance = SingleSuMSyBalance(sumsy,
                                                                        sumsy_interval = sumsy_interval,
                                                                        allow_negatives = allow_negatives),
                            income::Currency = CUR_0,
                            expenses::Currency = CUR_0,
                            types::Set{Symbol} = Set{Symbol}(),
                            behaviors::Vector{Function} = Vector{Function}())                            
    return SuMSyActor{Currency, typeof(balance)}(model,
                                model = model,
                                balance = balance,
                                income = income,
                                expenses = expenses,
                                types = types,
                                behaviors = behaviors)
end

get_sumsy(actor::SuMSyActor) = get_sumsy(get_balance(actor))

set_sumsy_active!(actor::SuMSyActor, flag::Bool) = set_sumsy_active!(actor.balance, flag)
set_sumsy_active!(actor::SuMSyActor, dep_entry::BalanceEntry, flag::Bool) = set_sumsy_active!(actor.balance, dep_entry, flag)
is_sumsy_active(actor::SuMSyActor) = is_sumsy_active(actor.balance)
is_sumsy_active(actor::SuMSyActor, dep_entry::BalanceEntry) = is_sumsy_active(actor.balance, dep_entry)
set_gi_eligible!(actor::SuMSyActor, flag::Bool) = set_gi_eligible!(actor.balance, flag)
is_gi_eligible(actor::SuMSyActor) = is_gi_eligible(actor.balance)

sumsy_assets(actor::SuMSyActor, step::Int = get_last_adjustment(actor.balance)) = sumsy_assets(actor.balance, timestamp = step)