using Agents

SINGLE_SUMSY = :SINGLE_SUMSY
MULTI_SUMSY = :MULTI_SUMSY

function add_properties!(model::ABM,
                        sumsy_interval::Int)
    properties = abmproperties(model)
    properties[:sumsy_interval] = sumsy_interval
    properties[:data_total_gi] = CUR_0
    properties[:data_total_demurrage] = CUR_0
end

"""
    create_sumsy_model(;sumsy_interval::Int,
                        balance_type::Type = SingleSuMSyBalance{Currency},
                        actor_type::Type = SuMSyActor{Currency, balance_type},
                        model_behaviors::Union{Nothing, Function, Vector{Function}} = nothing,
                        actors_first::Bool = false)
    * sumsy_interval::Int - Number of steps between SuMSy adjustments
    * balance_type::Type - Type of SuMSy balance
    * actor_type::Type - Type of SuMSy actor
    * model_behaviors::Union{Nothing, Function, Vector{Function}} - Vector of model behaviors
    * actors_first::Bool - Whether to process actor behaviors before model behaviors.
"""
function create_sumsy_model(;sumsy_interval::Int,
                            balance_type::Type = SingleSuMSyBalance{Currency},
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
                            initialize::Bool = true,
                            sumsy_interval::Int = model.sumsy_interval,
                            allow_negative_assets::Bool = true,
                            allow_negative_liabilities::Bool = true,
                            allow_negative_sumsy::Bool = false,
                            allow_negative_demurrage::Bool = false,
                            types::Set{Symbol} = Set{Symbol}(),
                            behaviors::Vector{Function} = Vector{Function}())

    if sumsy_type == SINGLE_SUMSY
        balance = SingleSuMSyBalance(sumsy,
                                    sumsy_interval = sumsy_interval,                                                                     
                                    activate = activate,
                                    gi_eligible = gi_eligible,
                                    initialize = initialize,
                                    allow_negative_assets = allow_negative_assets,
                                    allow_negative_liabilities = allow_negative_liabilities,
                                    allow_negative_sumsy = allow_negative_sumsy,
                                    allow_negative_demurrage = allow_negative_demurrage)
    else
        balance = MultiSuMSyBalance(sumsy,
                                    sumsy_interval = sumsy_interval, 
                                    SUMSY_DEP,                                                                             
                                    activate = activate,
                                    gi_eligible = gi_eligible,
                                    initialize = initialize,
                                    allow_negative_assets = allow_negative_assets,
                                    allow_negative_liabilities = allow_negative_liabilities,
                                    allow_negative_sumsy = allow_negative_sumsy,
                                    allow_negative_demurrage = allow_negative_demurrage)
    end



    actor = add_actor!(model, create_sumsy_actor!(model,
                                                    sumsy = sumsy,
                                                    sumsy_interval = sumsy_interval,
                                                    balance = balance,
                                                    types = types,
                                                    behaviors = behaviors))
    
    add_type!(actor, sumsy_type)

    return actor
end

function calculate_adjustments(model::ABM, actor::AbstractActor)
    balance = get_balance(actor)
    sumsy = get_sumsy(balance)

    return calculate_adjustments(balance, sumsy, model.sumsy_interval, get_step(model))
end

"""
    process_model_sumsy!(model::ABM)
    * model - SuMSy model

    Adjusts the SuMSy balance of all actors in the model.
    Registers guaranteed income and demurrage for the current step in actor.gi and actor.dem.
    Registers accumulative guaranteed income and demurrage for the model in model.data_total_gi and model.data_total_demurrage.
"""
function process_model_sumsy!(model::ABM)
    step = get_step(model)

    for actor in allagents(model)
        actor.gi = CUR_0
        actor.dem = CUR_0
    end

    if mod(step, model.sumsy_interval) == 0
        sum_gi = CUR_0
        sum_dem = CUR_0

        for actor in allagents(model)
            gi, dem = adjust_sumsy_balance!(get_balance(actor), step)
            sum_gi += gi
            sum_dem += dem

            actor.gi = gi
            actor.dem = dem
        end

        model.data_total_gi += sum_gi
        model.data_total_demurrage += sum_dem
    end
end

function process_actor_sumsy!(actor::AbstractActor)
    model = actor.model
    gi, dem = adjust_sumsy_balance!(get_balance(actor), get_step(model))
    
    actor.gi = gi
    actor.dem = dem

    model.data_total_gi += gi
    model.data_total_demurrage += dem
end

function transfer_sumsy!(model::ABM, source::AbstractActor, destination::AbstractActor, amount::Real)
    transfer_sumsy!(get_balance(source), get_balance(destination), amount, timestamp = get_step(model))
end