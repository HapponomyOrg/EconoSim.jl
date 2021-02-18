using Agents

function create_econo_model()
    properties = Dict{Symbol, Any}()
    properties[:step] = -1
    properties[:prices] = Dict{Blueprint, Price}()

    model = ABM(Actor, properties = properties)
end

get_step(model) = model.step

get_price(model, bp::Blueprint) = haskey(model.prices, bp) ? model.prices[bp] : nothing
set_price!(model, bp::Blueprint, price::Price) = (model.prices[bp] = price; model)

function econo_model_step!(model)
    model.step += 1

    for actor in allagents(model)
        for behavior in actor.model_behaviors
            behavior(model, actor)
        end
    end
end

function econo_step!(model, steps::Integer = 1)
    step!(model, actor_step!, econo_model_step!, steps, false)
end
