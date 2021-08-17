using Test
using EconoSim
using Agents

@testset "SuMSy contribution - none" begin
    model = create_sumsy_model(SuMSy(2000, 5000, 0.1, 10, seed = 500))
    actor = Actor()
    add_agent!(actor, model)

    run!(model, actor_step!, sumsy_model_step!, 40)

    @test sumsy_balance(actor) == 8350
    @test !(:contribution_balance in keys(model.properties))
end

@testset "SuMSy contribution - fixed" begin
    model = create_sumsy_model(SuMSy(2000, 5000, 0.1, 10, seed = 500),
                        fixed_contribution, 0, 0.1)
    actor = Actor()
    add_agent!(actor, model)

    run!(model, actor_step!, sumsy_model_step!, 40)

    @test sumsy_balance(actor) == 7160
    @test sumsy_balance(model.contribution_balance) == 1257.5
end

@testset "SuMSy contribution - on demand" begin
    model = create_sumsy_model(SuMSy(2000, 5000, 0.1, 10, seed = 500),
                        on_demand_contribution, 0, 0.1)
    actor = Actor()
    add_agent!(actor, model)

    request_contribution!(model, 100)
    sumsy_step!(model, 10)

    @test sumsy_balance(actor) == 2500
    @test sumsy_balance(model.contribution_balance) == 0
    @test model.contribution_shortage == 100

    request_contribution!(model, 100)
    sumsy_step!(model, 10)

    @test sumsy_balance(actor) == 4400
    @test sumsy_balance(model.contribution_balance) == 100
    @test model.contribution_shortage == 0

    request_contribution!(model, 500)
    sumsy_step!(model, 10)

    @test sumsy_balance(actor) == 5960
    @test sumsy_balance(model.contribution_balance) == 540
    @test model.contribution_shortage == 60

    request_contribution!(model, 1000)
    sumsy_step!(model, 10)

    @test sumsy_balance(actor) == 7268
    @test sumsy_balance(model.contribution_balance) == 1136
    @test model.contribution_shortage == 404
end
