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
    model = create_sumsy_model(1, register_gi_as_income = true, model_behaviors = process_model_sumsy!)
    @test abmproperties(model)[:register_gi_as_income]

    sumsy = SuMSy(1000, 0, 0.1)
    actor = add_sumsy_actor!(model, sumsy = sumsy, sumsy_interval = 1)

    run_econo_model!(model, 1)
    @test actor.income == 1900
end