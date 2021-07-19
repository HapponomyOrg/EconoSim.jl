using Agents

@enum CommonGoodMode none fixed_contribution on_demand_reserves

is_sumsy_active(actor::Actor) = is_sumsy_active(actor.balance)
process_sumsy!(sumsy::SuMSy, actor::Actor, step::Int) = process_sumsy!(sumsy, actor.balance, step)

function create_sumsy_model(sumsy::SuMSy,
                            common_good_mode::CommonGoodMode = none,
                            contribution_free::Real = 0,
                            contribution_tiers::Vector{T} = Vector{T}(),
                            interval::Int = sumsy.interval) where {T <: Tuple{Real, Real}}
    model = create_econo_model()
    model.properties[:common_good_mode] = common_good_mode

    if common_good_mode != none
        contribution = SuMSy(0, contribution_free, contribution_tiers, interval, 0)
        model.properties[:contribution] = contribution
    end

    return model
end

function create_susmsy_model(sumsy::SuMSy,
                            common_good_mode::CommonGoodMode = none,
                            contribution_free::Real = 0,
                            contribution::Real = 0,
                            interval::Int = sumsy.interval)
    return create_sumsy_model(sumsy, common_good_mode, contribution_free, [(0, contribution)], interval)
end

function sumsy_model_step!(model)
    econo_model_step!(model)

    for actor in allagents(model)
        process_sumsy!(sumsy, actor, model.step)

        if model.common_good_mode != none
            contribution = model.contribution

        end
    end
end

function make_sumsy!(model, actor::Actor; guaranteed_income::Bool = true)
end

sumsy_step!(model, steps::Integer = 1) = econo_step!(model, steps)
