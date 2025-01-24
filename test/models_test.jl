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

@testset "Registering SuMSy GI as income" begin
    model = create_sumsy_model(sumsy_interval = 30, model_behaviors = process_model_sumsy!)

    sumsy = SuMSy(1000, 0, 0.1)
    actor = add_sumsy_actor!(model, sumsy = sumsy, initialize = false)

    data = run_econo_model!(model, 1, adata = [:gi, :dem], mdata = [:total_gi, :total_demurrage], init = true)
    @test actor.gi == 0
    @test actor.dem == 0

    data = run_econo_model!(model, 29, adata = [:income], mdata = [:total_gi, :total_demurrage], init = true)
    @test actor.gi == 1000
    @test actor.dem == 0

    data = run_econo_model!(model, 30, adata = [:income], mdata = [:total_gi, :total_demurrage], init = true)
    @test actor.gi == 2000
    @test actor.dem == 100
end