using Agents

function add_properties(model::ABM,
                        sumsy::SuMSy,
                        contribution_settings::Union{SuMSy, Nothing})
    model.properties[:sumsy] = sumsy
    model.properties[:intervals] = Set([sumsy.interval])
    set_contribution_settings!(model, contribution_settings)
end

function create_single_sumsy_model(sumsy::SuMSy;
                                    actor_type::Type = MonetaryActor,
                                    model_behaviors::Union{Nothing, Function, Vector{Function}} = nothing,
                                    contribution_settings::Union{SuMSy, Nothing} = nothing)
    model = create_econo_model(actor_type, behavior_vector(model_behaviors))

    add_properties(model, sumsy, contribution_settings)

    return model
end

function create_unremovable_single_sumsy_model(sumsy::SuMSy;
                                                actor_type::Type = MonetaryActor,
                                                model_behaviors::Union{Nothing, Function, Vector{Function}} = nothing,
                                                contribution_settings::Union{SuMSy, Nothing} = nothing)
    model = create_unremovable_econo_model(actor_type, behavior_vector(model_behaviors))

    add_properties(model, sumsy, contribution_settings)

    return model
end

is_contribution_active(model::ABM) = !isnothing(model.contribution_settings)

function is_contribution_active(actor::AbstractActor)
    try
        !isnothing(actor.contribution_settings)
    catch
        return false
    end
end

function set_contribution_settings!(model::ABM,
                                    contribution_settings::Union{SuMSy, Nothing})
    try
        if model.contribution_settings.interval != contribution_settings.interval
            todo"Check whether old contribution interval is in use. Otherwise delete from set."
        end
    catch
    end

    model.properties[:contribution_settings] = contribution_settings

    if isnothing(contribution_settings)
        model.properties[:contribution_balance] = nothing
    else
        push!(model.intervals, contribution_settings.interval)

        try
            if isnothing(model.contribution_balance)
                model.contribution_balance = Balance(def_min_asset = typemin(Currency))
            end 
        catch
            model.properties[:contribution_balance] = Balance(def_min_asset = typemin(Currency))
        end
    end
    
end

get_contribution_settings(model::ABM) = model.contribution_settings

function collected_contributions(model)
    if is_contribution_active(model)
        return asset_value(model.contribution_balance, model.sumsy_dep_entry)
    else
        return CUR_0
    end
end

function reimburse_contribution!(model::ABM, amount::Real)
    total_contribution = CUR_0
    total_reimburse = CUR_0

    for actor in allagents(model)
        total_contribution += paid_contribution(actor)
    end

    for actor in allagents(model)
        reimburse_amount = amount * paid_contribution(actor) / total_contribution
        book_sumsy!(get_balance(actor), reimburse_amount)
        book_contribution!(actor, -amount)
        total_reimburse += reimburse_amount
    end

    book_asset!(model.contribution_balance, SUMSY_DEP, -total_reimburse)
end

function add_single_sumsy_actor!(model::ABM,
                                    actor::AbstractActor = MonetaryActor(next_id(model));
                                    sumsy::SuMSy = model.sumsy,
                                    activate::Bool = true,
                                    gi_eligible::Bool = true,
                                    initialize::Bool = true,
                                    contribution_settings::Union{SuMSy, Nothing} = model.contribution_settings)
    make_single_sumsy!(sumsy,
                        actor,
                        activate = activate,
                        gi_eligible = gi_eligible,
                        initialize = initialize,
                        contribution_settings = contribution_settings)

    if isnothing(contribution_settings)
        union!(model.intervals, sumsy.interval)
    else
        union!(model.intervals, [sumsy.interval, contribution_settings.interval])
    end

    add_agent!(actor, model)

    return actor
end

function calculate_adjustments(model::ABM, actor::AbstractActor)
    balance = get_balance(actor)
    sumsy = get_sumsy(balance)

    return calculate_adjustments(balance, sumsy, get_step(model))
end

function process_model_sumsy!(model::ABM)
    step = get_step(model)
    sumsy = model.sumsy

    if process_ready(sumsy, step)
        for actor in allagents(model)
            balance = get_balance(actor)
            
            income, demurrage = calculate_adjustments(balance, step, sumsy)
            book_sumsy!(balance, income - demurrage, step)
            set_last_adjustment!(balance, step)
        end
    end
end

function process_model_contribution!(model::ABM)
    step = get_step(model)
    contribution_settings = model.contribution_settings

    if is_contribution_active(model) && process_ready(model.contribution_settings, step)
        for actor in allagents(model)
            balance = get_balance(actor)
            _, contribution = calculate_adjustments(balance, step, contribution_settings)
            actor.contribution += contribution
            book_asset!(model.contribution_balance, get_sumsy_dep_entry(balance), contribution, timestamp = step)
            book_sumsy!(balance, -contribution, step)
        end
    end
end

function process_model_sumsy_contribution!(model::ABM)
end

function process_actor_sumsy!(model::ABM)
end

function process_actor_contribution!(model::ABM)
end

function process_actor_sumsy_contribution!(model::ABM)
end

function transfer_sumsy!(model::ABM, source::AbstractActor, destination::AbstractActor, amount::Real)
    transfer_sumsy!(get_balannce(source), get_balance(destination), amount, model.step)
end