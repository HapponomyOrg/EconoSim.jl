using Agents

SINGLE_SUMSY = :SINGLE_SUMSY
MULTI_SUMSY = :MULTI_SUMSY

function add_properties!(model::ABM,
                        sumsy_interval::Int)
    properties = abmproperties(model)
    properties[:sumsy_interval] = sumsy_interval
    properties[:total_gi] = CUR_0
    properties[:total_demurrage] = CUR_0
end

function create_sumsy_model(sumsy_interval::Int;
                            balance_type::Type = SingleSuMSyBalance,
                            actor_type::Type = SuMSyActor{Currency, balance_type},
                            model_behaviors::Union{Nothing, Function, Vector{Function}} = nothing,
                            actors_first::Bool = false)
    model = create_econo_model(actor_type, behavior_vector(model_behaviors), actors_first)

    add_properties!(model, sumsy_interval)

    return model
end

function add_sumsy_actor!(model::ABM;
                            sumsy_type::Symbol = SINGLE_SUMSY,
                            sumsy::SuMSy,
                            activate::Bool = true,
                            gi_eligible::Bool = true,
                            initialize::Bool = true)

    if sumsy_type == SINGLE_SUMSY
        balance = SingleSuMSyBalance(sumsy,                                                                                
                                    activate = activate,
                                    gi_eligible = gi_eligible,
                                    initialize = initialize)
    else
        balance = MultiSuMSyBalance(sumsy,
                                    SUMSY_DEP,                                                                             
                                    activate = activate,
                                    gi_eligible = gi_eligible,
                                    initialize = initialize)
    end
    
    actor = SuMSyActor(model, model = model, balance = balance)
    add_type!(actor, sumsy_type)
    add_agent!(actor, model)

    return actor
end

function calculate_adjustments(model::ABM, actor::AbstractActor)
    balance = get_balance(actor)
    sumsy = get_sumsy(balance)

    return calculate_adjustments(balance, sumsy, model.sumsy_interval, get_step(model))
end

function process_model_sumsy!(model::ABM)
    step = get_step(model)

    if mod(step, model.sumsy_interval) == 0
        sum_gi = CUR_0
        sum_dem = CUR_0

        for actor in allagents(model)
            gi, dem = adjust_sumsy_balance!(get_balance(actor), step)
            sum_gi += gi
            sum_dem += dem
        end

        model.total_gi += sum_gi
        model.total_demurrage += sum_dem
    end
end

function process_actor_sumsy!(actor::AbstractActor)
    model = actor.model
    gi, dem = adjust_sumsy_balance!(get_balance(actor), model.step)

    model.total_gi += gi
    model.total_demurrage += dem
end

function transfer_sumsy!(model::ABM, source::AbstractActor, destination::AbstractActor, amount::Real)
    transfer_sumsy!(get_balance(source), get_balance(destination), amount, timestamp = model.step)
end