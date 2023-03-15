using Test
using EconoSim
using Agents

@testset "SuMSy contribution - none" begin
    model = create_single_sumsy_model(SuMSy(2000, 5000, 0.1, 10, seed = 500), model_behaviors = process_model_sumsy!)
    actor = add_single_sumsy_actor!(model)

    run_econo_model!(model, 40, adata = [sumsy_assets])

    @test sumsy_assets(actor) == 8350
    @test !is_contribution_active(model)
end

@testset "SuMSy contribution" begin
    # model = create_sumsy_model(SuMSy(2000, 0, 0.1, 10),
    #                             contribution_settings = SuMSy(0, 0, 0.2, 10),
    #                             model_behaviors = process_model_sumsy_contribution)
    # actor = Actor()
    # add_agent!(actor, model)

    # book_asset!(actor.balance, SUMSY_DEP, 100, 0)

    # econo_step!(model, 10)
    # @test sumsy_assets(actor) == 2100
    # @test asset_value(model.contribution_balance, SUMSY_DEP) == 0
    # @test liability_value(model.contribution_balance, SUMSY_DEP) == 0

    # econo_step!(model, 10)
    # @test sumsy_assets(actor) == 3470
    # @test asset_value(model.contribution_balance, SUMSY_DEP) == 420
    # @test liability_value(model.contribution_balance, SUMSY_DEP) == 0
end