"""
SuMSyActor - Actor that has a SuMSy balance.
    * model::ABM
    * balance::SuMSyBalance
    * gi::Currency : Total guaranteed income received.
    * dem::Currency : Total demurrage paid.
"""
@agent struct SuMSyActor{C, B}(MonetaryActor{C, B}) <: AbstractBalanceActor
    data_gi::C
    data_demurrage::C
end

function create_sumsy_actor!(model::ABM;
                            sumsy::SuMSy,                                                                  
                            activate::Bool = true,
                            gi_eligible::Bool = true,
                            initialize::Bool = true,
                            sumsy_interval::Int = 30,
                            transactional::Bool = false,
                            allow_negative_assets::Bool = true,
                            allow_negative_liabilities::Bool = true,
                            allow_negative_sumsy::Bool = false,
                            allow_negative_demurrage::Bool = false,
                            balance::SuMSyBalance = SingleSuMSyBalance(sumsy,                                                                  
                                                                        activate = activate,
                                                                        gi_eligible = gi_eligible,
                                                                        initialize = initialize,
                                                                        sumsy_interval = sumsy_interval,
                                                                        transactional = transactional,
                                                                        allow_negative_assets = allow_negative_assets,
                                                                        allow_negative_liabilities = allow_negative_liabilities,
                                                                        allow_negative_sumsy = allow_negative_sumsy,
                                                                        allow_negative_demurrage = allow_negative_demurrage),
                            types::Set{Symbol} = Set{Symbol}(),
                            behaviors::Vector{Function} = Vector{Function}())                            
    actor =  SuMSyActor{Currency, typeof(balance)}(model,
                                model = model,
                                types = types,
                                behaviors = behaviors,
                                balance = balance,
                                income = CUR_0,
                                expenses = CUR_0,
                                data_gi = CUR_0,
                                data_demurrage = CUR_0)
    return actor
end

get_sumsy(actor::SuMSyActor) = get_sumsy(get_balance(actor))

set_sumsy_active!(actor::SuMSyActor, flag::Bool) = set_sumsy_active!(actor.balance, flag)
set_sumsy_active!(actor::SuMSyActor, dep_entry::BalanceEntry, flag::Bool) = set_sumsy_active!(actor.balance, dep_entry, flag)
is_sumsy_active(actor::SuMSyActor) = is_sumsy_active(actor.balance)
is_sumsy_active(actor::SuMSyActor, dep_entry::BalanceEntry) = is_sumsy_active(actor.balance, dep_entry)
set_gi_eligible!(actor::SuMSyActor, flag::Bool) = set_gi_eligible!(actor.balance, flag)
is_gi_eligible(actor::SuMSyActor) = is_gi_eligible(actor.balance)

sumsy_assets(actor::SuMSyActor, step::Int = get_last_adjustment(actor.balance)) = sumsy_assets(actor.balance, timestamp = step)