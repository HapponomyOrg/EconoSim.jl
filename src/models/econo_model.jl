using Agents

"""
    behavior_vector(behaviors::Union{Nothing, Function, Vector{Function}})

Create a Vector of functions based on the input.
If nothing is passed, an empty vector is returned.
If a function is passed, a vector with one element is returned.
If a vector is passed, the vector itself is returned.
"""
function behavior_vector(behaviors::Union{Nothing, Function, Vector{Function}})
    if behaviors isa Function
        return Vector{Function}([behaviors])
    elseif behaviors isa Vector
        return Vector{Function}(behaviors)
    else
        return Vector{Function}()
    end
end

function create_properties(model_behaviors::Union{Nothing, Function, Vector{Function}})
    properties = Dict{Symbol, Any}()
    properties[:step] = 0
    properties[:model_behaviors] = behavior_vector(model_behaviors)

    return properties
end

"""
    create_econo_model(model_behaviors::Union{Nothing, Function, Vector{Function}} = nothing)

Create a default model with 0 or more model behavior functions.
Each cycle the model runs, all model behavior functions are called in order.
"""
function create_econo_model(actor_type::Type = MonetaryActor{Currency},
                            model_behaviors::Union{Nothing, Function, Vector{Function}} = nothing,
                            actors_first::Bool = false)
    return ABM(actor_type,
                properties = create_properties(model_behaviors),
                agent_step! = actor_step!,
                model_step! = econo_model_step!,
                agents_first = actors_first)
end

function add_actor!(model::ABM, actor::AbstractActor)
    add_agent!(actor, model)

    return actor
end

"""
    function add_model_behavior!(model, behavior::Function; position::Integer = length(model.model_behaviors) + 1)

Attempts to insert a new model behaviour at the specified position.
If the position is greater than the length of the model.behaviors vector, it is appended.
If the position is less than 1, it is prepended.
"""
function add_model_behavior!(model, behavior::Function; position::Integer = length(model.model_behaviors) + 1)
    if position < 1
        position = 1
    elseif position > length(model.model_behaviors) + 1
        position = length(model.model_behaviors) + 1
    end

    insert!(model.model_behaviors, position, behavior)
    
    return model
end

has_model_behavior(model, behavior::Function) = behavior in model.model_behaviors
delete_model_behavior!(model, behavior::Function) = (delete_element!(model.model_behaviors, behavior); model)
clear_model_behaviors(model) = (empty!(model.model_behaviors); model)

get_step(model) = model.step

function econo_model_step!(model::ABM)
    for behavior in model.model_behaviors
        behavior(model)
    end
end

"""
    function stepper!(model::ABM, step::Integer)

    This function makes sure the econo_model_step! and actor_step! functions have access to the current step of the model.
"""
function stepper!(model::ABM, step::Integer)
    model.step += 1

    return step >= model.run_steps
end

function econo_step!(model::ABM, steps::Integer = 1)
    abmproperties(model)[:run_steps] = steps

    step!(model, actor_step!, econo_model_step!, stepper!)
end

function run_econo_model!(model::ABM, steps::Integer; kwargs...)
    abmproperties(model)[:run_steps] = steps

    run!(model, stepper!; kwargs...)
end