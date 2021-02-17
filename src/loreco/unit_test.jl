using Test
using Agents
using DataStructures
using ..Utilities
using ..Production
using ..Finance
using ..Econo_Sim
using ..Loreco

@testset "Loreco model" begin
    now = time()
    # Create the Loreco model.
    model = init_loreco_model()

    # Execute 300 default steps
    econo_step!(model, 3000)
    done = time() - now

    sumsy_data = Dict{Symbol, Float64}(CONSUMER => 0, BAKER => 0, TV_MERCHANT => 0, GOVERNANCE => 0)

    for actor in allagents(model)
        if has_type(actor, CONSUMER)
            symbol = CONSUMER
        elseif has_type(actor, BAKER)
            symbol = BAKER
        elseif has_type(actor, TV_MERCHANT)
            symbol = TV_MERCHANT
        elseif has_type(actor, GOVERNANCE)
            symbol = GOVERNANCE
        end

        sumsy_data[symbol] = sumsy_data[symbol] + sumsy_balance(actor)
    end

    sumsy_data[CONSUMER] = round(sumsy_data[CONSUMER] / 380, digits = 2)
    sumsy_data[BAKER] = round(sumsy_data[BAKER] / 15, digits = 2)
    sumsy_data[TV_MERCHANT] = round(sumsy_data[TV_MERCHANT] / 20, digits = 2)
end
