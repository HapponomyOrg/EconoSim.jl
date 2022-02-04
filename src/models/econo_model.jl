using Agents

function behavior_vector(behaviors::Union{Nothing, Function, Vector{Function}})
    if behaviors isa Function
        return Vector{Function}([behaviors])
    elseif behaviors isa Vector
        return Vector{Function}(behaviors)
    else
        return Vector{Function}()
    end
end

function create_econo_model(model_behaviors::Union{Nothing, Function, Vector{Function}} = nothing)
    properties = Dict{Symbol, Any}()
    properties[:step] = -1
    properties[:prices] = Dict{Blueprint, Price}()
    properties[:model_behaviors] = behavior_vector(model_behaviors)

    return ABM(Actor, properties = properties)
end

has_model_behavior(model, behavior::Function) = behavior in model.model_behaviors
add_model_behavior!(model, behavior::Function) = (push!(model.model_behaviors, behavior); model)
delete_model_behavior!(model, behavior::Function) = (delete_element!(model.model_behaviors, behavior); model)
clear_model_behaviors(model) = (empty!(model.model_behaviors); model)

get_step(model) = model.step

get_price(model, bp::Blueprint) = haskey(model.prices, bp) ? model.prices[bp] : nothing
set_price!(model, bp::Blueprint, price::Price) = (model.prices[bp] = price; model)

function econo_model_step!(model)
    model.step += 1

    for behavior in model.model_behaviors
        behavior(model)
    end
end

function econo_step!(model, steps::Integer = 1)
    step!(model, actor_step!, econo_model_step!, steps, false)
end

function run_econo_model!(model, steps, kwargs...)
    run!(model, actor_step!, econo_model_step!, steps, agents_first = false; kwargs...)
end