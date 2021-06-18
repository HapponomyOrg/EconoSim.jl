using Agents

@enum CommonGoodMode none fixed_contribution on_demand_reserves

function create_sumsy_model(sumsy::SuMSy,
                            common_good_mode::CommonGoodMode = none,
                            contribution_free::Real = 0,
                            contribution_tiers::Vector{T} = Vector{T}(),
                            interval::Int = sumsy.interval) where {T <: Tuple{Real, Real}}
    model = create_econo_model()

    if common_good_mode != none
        contribution = SuMSy(0, contribution_free, contribution_tiers, sumsy.interval, 0)

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
