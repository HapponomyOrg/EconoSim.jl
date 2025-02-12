using Test
using EconoSim
using Agents

@testset "Adding and deleting model behaviors" begin
    model_behavior_function(model) = model

    model = create_econo_model()

    @test !has_model_behavior(model, model_behavior_function)
    add_model_behavior!(model, model_behavior_function)
    @test has_model_behavior(model, model_behavior_function)

    delete_model_behavior!(model, model_behavior_function)
    @test !has_model_behavior(model, model_behavior_function)
end

@testset "Running SuMSy model" begin
    model = create_sumsy_model(sumsy_interval = 30, model_behaviors = process_model_sumsy!)

    sumsy = SuMSy(1000, 0, 0.1)
    actor_1 = add_sumsy_actor!(model, sumsy = sumsy, initialize = false)
    actor_2 = add_sumsy_actor!(model, sumsy = sumsy, initialize = false)

    data = run_econo_model!(model, 1, adata = [:gi, :dem], mdata = [:data_total_gi, :data_total_demurrage], init = true)
    @test data[2][!, :data_total_gi][end] == 0
    @test data[2][!, :data_total_demurrage][end] == 0
    @test actor_1.gi == actor_2.gi == 0
    @test actor_1.dem == actor_2.dem == 0
    @test asset_value(get_balance(actor_1), SUMSY_DEP) == asset_value(get_balance(actor_2), SUMSY_DEP) == 0

    data = run_econo_model!(model, 29, adata = [:gi, :dem], mdata = [:data_total_gi, :data_total_demurrage], init = true)
    @test data[2][!, :data_total_gi][end] == 2000
    @test data[2][!, :data_total_demurrage][end] == 0
    @test actor_1.gi == actor_2.gi == 1000
    @test actor_1.dem == actor_2.dem == 0
    @test asset_value(get_balance(actor_1), SUMSY_DEP) == asset_value(get_balance(actor_2), SUMSY_DEP) == 1000

    data = run_econo_model!(model, 30, adata = [:gi, :dem], mdata = [:data_total_gi, :data_total_demurrage], init = true)
    @test data[2][!, :data_total_gi][end] == 4000
    @test data[2][!, :data_total_demurrage][end] == 200
    @test actor_1.gi == actor_2.gi == 1000
    @test actor_1.dem == actor_2.dem == 100
    @test asset_value(get_balance(actor_1), SUMSY_DEP) == asset_value(get_balance(actor_2), SUMSY_DEP) == 1900
end