using Test
using Intervals
using EconoSim
using FixedPointDecimals

@testset "Balance" begin
    b = Balance()
    asset1 = BalanceEntry("Asset 1")
    asset2 = BalanceEntry("Asset 2")
    liability1 = BalanceEntry("Liability 1")
    liability2 = BalanceEntry("Liability 2")

    @test assets_value(b) == 0
    @test liabilities_value(b) == 0
    @test equity(b) == 0
    @test validate(b)

    book_asset!(b, asset1, 10)
    @test asset_value(b, asset1) == 10
    @test assets_value(b) == 10
    @test liabilities_value(b) == 10
    @test liabilities_net_value(b) == 0
    @test equity(b) == 10
    @test validate(b)

    book_liability!(b, liability1, 10)
    @test liability_value(b, liability1) == 10
    @test assets_value(b) == 10
    @test liabilities_value(b) == 10
    @test liabilities_net_value(b) == 10
    @test equity(b) == 0
    @test validate(b)

    book_asset!(b, asset2, 5)
    @test asset_value(b, asset2) == 5
    @test assets_value(b) == 15
    @test liabilities_value(b) == 15
    @test liabilities_net_value(b) == 10
    @test equity(b) == 5
    @test validate(b)

    book_liability!(b, liability2, 1)
    @test liability_value(b, liability2) == 1
    @test assets_value(b) == 15
    @test liabilities_value(b) == 15
    @test liabilities_net_value(b) == 11
    @test equity(b) == 4
    @test validate(b)

    book_asset!(b, asset1, 100, set_to_value = true)
    @test asset_value(b, asset1) == 100
    @test assets_value(b) == 105

    book_liability!(b, liability1, 200, set_to_value = true)
    @test liability_value(b, liability1) == 200
    @test assets_value(b) == 105
    @test liabilities_value(b) == 105
    @test liabilities_net_value(b) == 201
end

@testset "Min balances" begin
    e1 = BalanceEntry("E1")
    e2 = BalanceEntry("E2")
    b = Balance()

    min_asset!(b, e1, typemin(Currency))
    min_liability!(b, e2, typemin(Currency))

    @test min_asset(b, e1) < 0
    @test min_asset(b, e2) == 0

    @test min_liability(b, e1) == 0
    @test min_liability(b, e2) < 0

    @test book_asset!(b, e1, -50)
    @test !book_asset!(b, e2, -50)

    @test !book_liability!(b, e1, -50)
    @test book_liability!(b, e2, -50)

    min_liability!(b, EQUITY, 0)
    @test min_liability(b, EQUITY) < 0
end

@testset "Transfers" begin
    a = BalanceEntry("Asset")
    l = BalanceEntry("Liability")
    d = BalanceEntry("Dual")

    b1 = Balance()
    book_asset!(b1, a, 10)
    book_liability!(b1, l, 10)
    book_asset!(b1, d, 20)
    book_liability!(b1, d, 20)

    b2 = Balance()

    transfer_asset!(b1, b2, a, 5)
    @test asset_value(b1, a) == 5
    @test asset_value(b2, a) == 5

    transfer_liability!(b1, b2, l, 1)
    @test liability_value(b1, l) == 9
    @test liability_value(b2, l) == 1

    transfer!(b1, asset, b2, liability, d, 2)
    transfer!(b1, liability, b2, asset, d, 3)
    @test asset_value(b1, d) == 18
    @test liability_value(b1, d) == 17
    @test asset_value(b2, d) == 3
    @test liability_value(b2, d) == 2
end

@testset "SuMSy dem tiers" begin
    tiers = make_tiers([(0, 0.1), (10, 0.2), (20, 0.3)])
    @test length(tiers) == 3
    @test tiers[1][1] isa Interval

    @test first(tiers[1][1]) == 0
    @test last(tiers[1][1]) == 10
    @test is_left_open(tiers[1][1])
    @test is_right_closed(tiers[1][1])
    @test tiers[1][2] == 0.1

    @test first(tiers[2][1]) == 10
    @test last(tiers[2][1]) == 20
    @test is_left_open(tiers[2][1])
    @test is_right_closed(tiers[2][1])
    @test tiers[2][2] == 0.2

    @test first(tiers[3][1]) == 20
    @test last(tiers[3][1]) === nothing
    @test is_left_open(tiers[3][1])
    @test is_right_unbounded(tiers[3][1])
    @test tiers[3][2] == 0.3

    tiers = make_tiers([(0, 0.1), (10, 0.2)])
    @test first(tiers[1][1]) == 0
    @test last(tiers[1][1]) == 10
    @test is_left_open(tiers[1][1])
    @test is_right_closed(tiers[1][1])
    @test tiers[1][2] == 0.1

    @test first(tiers[2][1]) == 10
    @test last(tiers[2][1]) === nothing
    @test is_left_open(tiers[2][1])
    @test is_right_unbounded(tiers[2][1])
    @test tiers[2][2] == 0.2

    tiers = make_tiers([(0, 0.1)])
    @test length(tiers) == 1
    @test first(tiers[1][1]) == 0
    @test last(tiers[1][1]) === nothing
    @test is_left_open(tiers[1][1])
    @test is_right_unbounded(tiers[1][1])
    @test tiers[1][2] == 0.1
end

@testset "SuMSy telo" begin
    sumsy = SuMSy(4000, 50000, [(0, 0.01), (50000, 0.02), (150000, 0.05)], 10)

    @test telo(sumsy) == 230000
    balance = SingleSuMSyBalance(sumsy, initialize = true)
    book_sumsy!(balance, telo(sumsy) - 4000, timestamp = 0)
    @test sumsy_assets(balance, timestamp = 0) == 230000
    @test EconoSim.calculate_adjustments(balance, 10) == (sumsy.income.guaranteed_income, sumsy.income.guaranteed_income)
end

@testset "SingleSuMSyBalance - transfer between SuMSy and non-SuMSy" begin
    sumsy = SuMSy(1000, 0, 0.1, 10)

    b1 = SingleSuMSyBalance(sumsy)
    b2 = SingleSuMSyBalance(sumsy)

    book_asset!(b1, get_sumsy_dep_entry(b1), 100)
    book_asset!(b1, DEPOSIT, 100)

    book_asset!(b2, get_sumsy_dep_entry(b2), 100)
    book_asset!(b2, DEPOSIT, 100)

    @test transfer_asset!(b1, get_sumsy_dep_entry(b1), b2, get_sumsy_dep_entry(b2), 10)
    @test transfer_asset!(b2, get_sumsy_dep_entry(b2), b1, get_sumsy_dep_entry(b1), 10)

    @test transfer_asset!(b1, DEPOSIT, b2, get_sumsy_dep_entry(b2), 10) == false
    @test transfer_asset!(b2, DEPOSIT, b1, get_sumsy_dep_entry(b1), 10) == false

    @test transfer_asset!(b1, get_sumsy_dep_entry(b1), b2, DEPOSIT, 10) == false
    @test transfer_asset!(b2, get_sumsy_dep_entry(b2), b1, DEPOSIT, 10) == false
end

@testset "SingleSuMSyBalance - non transactional" begin
    sumsy = SuMSy(1000, 0, 0.1, 10, seed = 500, transactional = false)

    balance = SingleSuMSyBalance(sumsy, activate = true, initialize = true)
    @test sumsy_assets(balance, timestamp = 0) == 1500
    @test sumsy_assets(balance, timestamp = 10) == 2350
    @test sumsy_assets(balance, timestamp = 20) == 3115

    balance = SingleSuMSyBalance(sumsy, activate = true, initialize = false)
    @test sumsy_assets(balance, timestamp = 0) == 0
    @test sumsy_assets(balance, timestamp = 10) == 1000
    @test sumsy_assets(balance, timestamp = 20) == 1900
end

@testset "SingleSuMSyBalance - transactional" begin
    sumsy = SuMSy(1000, 0, 0.1, 10, seed = 500, transactional = true)

    balance = SingleSuMSyBalance(sumsy, activate = true, initialize = true)
    @test sumsy_assets(balance, timestamp = 0) == 1500
    @test sumsy_assets(balance, timestamp = 5) == 1925

    balance = SingleSuMSyBalance(sumsy, activate = true, initialize = false)
    @test sumsy_assets(balance, timestamp = 0) == 0
    @test sumsy_assets(balance, timestamp = 5) == 500
    @test sumsy_assets(balance, timestamp = 10) == 1000

    balance = SingleSuMSyBalance(sumsy, activate = false, initialize = true)
    @test sumsy_assets(balance, timestamp = 0) == 1500
    @test sumsy_assets(balance, timestamp = 5) == 1500
    @test sumsy_assets(balance, timestamp = 10) == 1500
end

@testset "SingleSuMSyBalance - transfer - non transactional" begin
    sumsy = SuMSy(2000, 25000, 0.1, 30, transactional = false)
    balance1 = SingleSuMSyBalance(sumsy, initialize = true)
    balance2 = SingleSuMSyBalance(sumsy, initialize = true)

    @test transfer_sumsy!(balance1, balance2, 1500)
    @test sumsy_assets(balance1, timestamp = 0) == 500
    @test sumsy_assets(balance2, timestamp = 0) == 3500

    @test !transfer_sumsy!(balance1, balance2, 1000)
    @test sumsy_assets(balance1, timestamp = 0) == 500
    @test sumsy_assets(balance2, timestamp = 0) == 3500

    @test transfer_sumsy!(balance1, balance2, -1500)
    @test sumsy_assets(balance1, timestamp = 0) == 2000
    @test sumsy_assets(balance2, timestamp = 0) == 2000

    @test !transfer_sumsy!(balance1, balance2, -2500)
    @test sumsy_assets(balance1, timestamp = 0) == 2000
    @test sumsy_assets(balance2, timestamp = 0) == 2000
end

@testset "SingleSuMSyBalance demurrage - single - non transactional" begin
    sumsy = SuMSy(2000, 25000, 0.1, 30, seed = 5000)
    balance = SingleSuMSyBalance(sumsy, initialize = true)

    @test sumsy_assets(balance) == 7000
    book_asset!(balance, get_sumsy_dep_entry(balance), telo(sumsy), set_to_value = true)
    @test EconoSim.calculate_timerange_adjustments(balance,
                                                    sumsy,
                                                    get_sumsy_dep_entry(balance),
                                                    is_gi_eligible(balance),
                                                    get_dem_free(balance),
                                                    sumsy.interval) == (sumsy.income.guaranteed_income, sumsy.income.guaranteed_income)
    clear!(balance)

    adjust_sumsy_balance!(balance, 0)
    @test sumsy_assets(balance, timestamp = 0) == 0

    adjust_sumsy_balance!(balance, 30)
    @test sumsy_assets(balance, timestamp = 30) == 2000

    book_sumsy!(balance, 98000)
    @test EconoSim.calculate_timerange_adjustments(balance,
                                                    sumsy,
                                                    get_sumsy_dep_entry(balance),
                                                    is_gi_eligible(balance),
                                                    get_dem_free(balance),
                                                    sumsy.interval) == (2000, 7500)
    @test sumsy_assets(balance, timestamp = 30) == 100000
end

@testset "SingleSuMSyBalance - demurage - single - transactional" begin
    sumsy = SuMSy(2000, 25000, 0.1, 30, seed = 5000, transactional = true)
    balance = SingleSuMSyBalance(sumsy, initialize = true)

    @test sumsy_assets(balance) == 7000
    book_sumsy!(balance, 23000)
    @test sumsy_assets(balance) == 30000

    book_sumsy!(balance, 10000, timestamp = 15)
    @test sumsy_assets(balance) == 40750
    @test sumsy_assets(balance, timestamp = 15) == 40750

    book_sumsy!(balance, 250, timestamp = 15)
    @test sumsy_assets(balance, timestamp = 15) == 41000

    @test EconoSim.calculate_adjustments(balance, 30) == (1000, 800)
    @test sumsy_assets(balance, timestamp = 30) == 41200
end

@testset "SingleSuMSyBalance - demurrage - tiers - non transactional" begin
    sumsy = SuMSy(2000, 50000, [(0, 0.1), (50000, 0.2), (150000, 0.5)], 10, transactional = false)
    balance = SingleSuMSyBalance(sumsy)
    book_asset!(balance, get_sumsy_dep_entry(balance), telo(sumsy), set_to_value = true)
    @test EconoSim.calculate_timerange_adjustments(balance,
                                                    sumsy,
                                                    get_sumsy_dep_entry(balance),
                                                    is_gi_eligible(balance),
                                                    get_dem_free(balance),
                                                    sumsy.interval) == (sumsy.income.guaranteed_income, sumsy.income.guaranteed_income)

    clear!(balance)
    book_sumsy!(balance, 210000, timestamp = 0)

    @test get_dem_free(balance) == 50000
    @test EconoSim.calculate_adjustments(balance, 10) == (2000, 30000)

    adjust_sumsy_balance!(balance, 10)
    @test sumsy_assets(balance, timestamp = 10) == 182000
end

@testset "SingleSuMSyBalance - demurrage - tiers - transactional" begin
    sumsy = SuMSy(2000, 50000, [(0, 0.1), (50000, 0.2), (150000, 0.5)], 10, transactional = true)
    balance = SingleSuMSyBalance(sumsy, initialize = true)
    @test sumsy_assets(balance) == 2000

    book_sumsy!(balance, 208000, timestamp = 0)
    @test sumsy_assets(balance) == 210000
    book_sumsy!(balance, 100000, timestamp = 5)
    @test sumsy_assets(balance) == sumsy_assets(balance, timestamp = 5)
    @test sumsy_assets(balance) == 296000

    @test EconoSim.calculate_adjustments(balance, 10) == (1000, 36500)
    @test sumsy_assets(balance, timestamp = 10) == 260500
end

@testset "SingleSuMSyBalance - demurrage - override SuMSy - non transactional" begin
    sumsy = SuMSy(2000, 50000, [(0, 0.1), (50000, 0.2), (150000, 0.5)], 10, transactional = false)
    balance = SingleSuMSyBalance(sumsy, initialize = true)

    @test get_dem_free(balance) == 50000
    @test asset_value(balance, get_sumsy_dep_entry(balance)) == 2000
    @test sumsy_assets(balance, timestamp = 0) == 2000
    
    set_sumsy!(balance,
                SuMSy(1000, 0, 0, 10, seed = 10000, transactional = false),
                reset_balance = true,
                reset_dem_free = true)
    
    @test get_dem_free(balance) == 0
    @test asset_value(balance, get_sumsy_dep_entry(balance)) == 11000
    @test sumsy_assets(balance, timestamp = 0) == 11000
    @test sumsy_assets(balance, timestamp = 20) == 13000

    set_sumsy!(balance,
                SuMSy(5000, 1000, 0.1, 10, seed = 0, transactional = false),
                reset_balance = true,
                reset_dem_free = false)
    
    @test get_dem_free(balance) == 0
    @test asset_value(balance, get_sumsy_dep_entry(balance)) == 5000
    @test sumsy_assets(balance, timestamp = 0) == 5000
    @test sumsy_assets(balance, timestamp = 20) == 13550

    set_sumsy!(balance,
                SuMSy(3000, 20000, 0.2, 10, seed = 10, transactional = false),
                reset_balance = false,
                reset_dem_free = true)
    
    @test get_dem_free(balance) == 20000
    @test asset_value(balance, get_sumsy_dep_entry(balance)) == 5000
    @test sumsy_assets(balance, timestamp = 0) == 5000
    @test sumsy_assets(balance, timestamp = 20) == 11000
end

@testset "SingleSuMSyBalance - demurrage - overrides - transactional" begin
    sumsy = SuMSy(2000, 50000, [(0, 0.1), (50000, 0.2), (150000, 0.5)], 10, transactional = true)
    balance = SingleSuMSyBalance(sumsy, initialize = true)
    @test sumsy_assets(balance, timestamp = 0) == 2000
    
    set_sumsy!(balance,
                SuMSy(1000, 0, 0, 10, seed = 10000, transactional = true),
                reset_balance = true,
                reset_dem_free = true)
    
    @test asset_value(balance, get_sumsy_dep_entry(balance)) == 11000
    @test sumsy_assets(balance, timestamp = 10) == 12000
    @test sumsy_assets(balance, timestamp = 20) == 13000

    set_sumsy!(balance,
                SuMSy(2000, 5000, 0.1, 10, seed = 0, transactional = true),
                reset_balance = false,
                reset_dem_free = true)
    
    @test asset_value(balance, get_sumsy_dep_entry(balance)) == 11000
    @test sumsy_assets(balance, timestamp = 10) == 12400
    @test sumsy_assets(balance, timestamp = 15) == 13030
    @test sumsy_assets(balance, timestamp = 20) == 13660
end

@testset "SingleSuMSyBalance inactive" begin
    sumsy = SuMSy(4000, 50000, [(0, 0.1), (50000, 0.2), (150000, 0.5)], 10)
    balance = SingleSuMSyBalance(sumsy)

    book_asset!(balance, get_sumsy_dep_entry(balance), 210000, set_to_value = true)
    set_sumsy_active!(balance, false)

    adjust_sumsy_balance!(balance, 10)
    @test sumsy_assets(balance, timestamp = 10) == 210000
end

@testset "SingleSuMSyBalance - SuMSy overrides" begin
    sumsy = SuMSy(2000, 50000, [(0, 0.1), (50000, 0.2), (150000, 0.5)], 10)
    balance = SingleSuMSyBalance(sumsy)

    set_sumsy!(balance, SuMSy(sumsy, seed = 1000), reset_balance = true, reset_dem_free = true)
    @test sumsy_assets(balance) == 3000

    set_sumsy!(balance, SuMSy(sumsy, guaranteed_income = 5000), reset_balance = false, reset_dem_free = false)
    adjust_sumsy_balance!(balance, 10)
    @test sumsy_assets(balance) == 8000

    set_sumsy!(balance, SuMSy(sumsy, dem_free = 3000), reset_balance = false, reset_dem_free = true)
    @test get_dem_free(balance) == 3000
    @test EconoSim.calculate_adjustments(balance, 20) == (2000, 500)
    adjust_sumsy_balance!(balance, 20)
    @test sumsy_assets(balance) == 9500
end

@testset "SingleSuMSyBalance - demurrage free transfer" begin
    sumsy = SuMSy(2000, 50000, [(0, 0.1), (50000, 0.2), (150000, 0.5)], 10)
    balance1 = SingleSuMSyBalance(sumsy)
    balance2 = SingleSuMSyBalance(sumsy)

    transfer_dem_free!(balance1, balance2, 10000)
    @test get_dem_free(balance1) == 40000
    @test get_dem_free(balance2) == 60000
end

@testset "MultiSuMSyBalance - non transactional" begin
    sumsy = SuMSy(1000, 0, 0.1, 10, seed = 500, transactional = false)

    balance = MultiSuMSyBalance(sumsy, SUMSY_DEP, activate = true, initialize = true)
    @test sumsy_assets(balance, SUMSY_DEP, timestamp = 0) == 1500
    @test sumsy_assets(balance, SUMSY_DEP, timestamp = 10) == 2350
    @test sumsy_assets(balance, SUMSY_DEP, timestamp = 20) == 3115

    balance = MultiSuMSyBalance(sumsy, SUMSY_DEP, activate = true, initialize = false)
    @test sumsy_assets(balance, SUMSY_DEP, timestamp = 0) == 0
    @test sumsy_assets(balance, SUMSY_DEP, timestamp = 10) == 1000
    @test sumsy_assets(balance, SUMSY_DEP, timestamp = 20) == 1900
end

@testset "MultiSuMSyBalance - transactional" begin
    sumsy = SuMSy(1000, 0, 0.1, 10, seed = 500, transactional = true)

    balance = MultiSuMSyBalance(sumsy, SUMSY_DEP, activate = true, initialize = true)
    @test sumsy_assets(balance, SUMSY_DEP, timestamp = 0) == 1500
    @test sumsy_assets(balance, SUMSY_DEP, timestamp = 5) == 1925

    balance = MultiSuMSyBalance(sumsy, SUMSY_DEP, activate = true, initialize = false)
    @test sumsy_assets(balance, SUMSY_DEP, timestamp = 0) == 0
    @test sumsy_assets(balance, SUMSY_DEP, timestamp = 5) == 500
    @test sumsy_assets(balance, SUMSY_DEP, timestamp = 10) == 1000

    balance = MultiSuMSyBalance(sumsy, SUMSY_DEP, activate = false, initialize = true)
    @test sumsy_assets(balance, SUMSY_DEP, timestamp = 0) == 1500
    @test sumsy_assets(balance, SUMSY_DEP, timestamp = 5) == 1500
    @test sumsy_assets(balance, SUMSY_DEP, timestamp = 10) == 1500
end

@testset "MultiSuMSyBalance - transfer - non transactional" begin
    sumsy = SuMSy(2000, 25000, 0.1, 30)
    balance1 = MultiSuMSyBalance(sumsy, SUMSY_DEP)
    balance2 = MultiSuMSyBalance(sumsy, SUMSY_DEP)

    @test transfer_sumsy!(balance1, balance2, SUMSY_DEP, 1500)
    @test sumsy_assets(balance1, SUMSY_DEP, timestamp = 0) == 500
    @test sumsy_assets(balance2, SUMSY_DEP, timestamp = 0) == 3500

    @test !transfer_sumsy!(balance1, balance2, SUMSY_DEP, 1000)
    @test sumsy_assets(balance1, SUMSY_DEP, timestamp = 0) == 500
    @test sumsy_assets(balance2, SUMSY_DEP, timestamp = 0) == 3500

    @test transfer_sumsy!(balance1, balance2, SUMSY_DEP, -1500)
    @test sumsy_assets(balance1, SUMSY_DEP, timestamp = 0) == 2000
    @test sumsy_assets(balance2, SUMSY_DEP, timestamp = 0) == 2000

    @test !transfer_sumsy!(balance1, balance2, SUMSY_DEP, -2500)
    @test sumsy_assets(balance1, SUMSY_DEP, timestamp = 0) == 2000
    @test sumsy_assets(balance2, SUMSY_DEP, timestamp = 0) == 2000
end

@testset "MultiSuMSyBalance demurrage - single - non transactional" begin
    sumsy = SuMSy(2000, 25000, 0.1, 30, seed = 5000)
    balance = MultiSuMSyBalance(sumsy, SUMSY_DEP)

    @test sumsy_assets(balance, SUMSY_DEP) == 7000
    book_asset!(balance, SUMSY_DEP, telo(sumsy), set_to_value = true)
    @test EconoSim.calculate_timerange_adjustments(balance,
                                                    sumsy,
                                                    SUMSY_DEP,
                                                    is_gi_eligible(balance, SUMSY_DEP),
                                                    get_dem_free(balance, SUMSY_DEP),
                                                    sumsy.interval) == (sumsy.income.guaranteed_income, sumsy.income.guaranteed_income)
    clear!(balance)

    adjust_sumsy_balance!(balance, SUMSY_DEP, 0)
    @test sumsy_assets(balance, SUMSY_DEP, timestamp = 0) == 0

    adjust_sumsy_balance!(balance, SUMSY_DEP, 30)
    @test sumsy_assets(balance, SUMSY_DEP, timestamp = 30) == 2000

    book_sumsy!(balance, SUMSY_DEP, 98000)
    @test EconoSim.calculate_timerange_adjustments(balance,
                                                    sumsy,
                                                    SUMSY_DEP,
                                                    is_gi_eligible(balance, SUMSY_DEP),
                                                    get_dem_free(balance, SUMSY_DEP),
                                                    sumsy.interval) == (2000, 7500)
    @test sumsy_assets(balance, SUMSY_DEP, timestamp = 30) == 100000
end

@testset "MultiSuMSyBalance - demurage - single - transactional" begin
    sumsy = SuMSy(2000, 25000, 0.1, 30, seed = 5000, transactional = true)
    balance = MultiSuMSyBalance(sumsy, SUMSY_DEP)

    @test sumsy_assets(balance, SUMSY_DEP) == 7000
    book_sumsy!(balance, SUMSY_DEP, 23000)
    @test sumsy_assets(balance, SUMSY_DEP) == 30000

    book_sumsy!(balance, SUMSY_DEP, 10000, timestamp = 15)
    @test sumsy_assets(balance, SUMSY_DEP) == 40750
    @test sumsy_assets(balance, SUMSY_DEP, timestamp = 15) == 40750

    book_sumsy!(balance, SUMSY_DEP, 250, timestamp = 15)
    @test sumsy_assets(balance, SUMSY_DEP, timestamp = 15) == 41000

    @test EconoSim.calculate_adjustments(balance, SUMSY_DEP, 30) == (1000, 800)
    @test sumsy_assets(balance, SUMSY_DEP, timestamp = 30) == 41200
end

@testset "MultiSuMSyBalance - demurrage - tiers - non transactional" begin
    sumsy = SuMSy(2000, 50000, [(0, 0.1), (50000, 0.2), (150000, 0.5)], 10, transactional = false)
    balance = MultiSuMSyBalance(sumsy, SUMSY_DEP)
    book_asset!(balance, SUMSY_DEP, telo(sumsy), set_to_value = true)
    @test EconoSim.calculate_timerange_adjustments(balance,
                                                    sumsy,
                                                    SUMSY_DEP,
                                                    is_gi_eligible(balance, SUMSY_DEP),
                                                    get_dem_free(balance, SUMSY_DEP),
                                                    sumsy.interval) == (sumsy.income.guaranteed_income, sumsy.income.guaranteed_income)

    clear!(balance)
    book_sumsy!(balance, SUMSY_DEP, 210000, timestamp = 0)

    @test get_dem_free(balance, SUMSY_DEP) == 50000
    @test EconoSim.calculate_adjustments(balance, SUMSY_DEP, 10) == (2000, 30000)

    adjust_sumsy_balance!(balance, SUMSY_DEP, 10)
    @test sumsy_assets(balance, SUMSY_DEP, timestamp = 10) == 182000
end

@testset "MultiSuMSyBalance - demurrage - tiers - transactional" begin
    sumsy = SuMSy(2000, 50000, [(0, 0.1), (50000, 0.2), (150000, 0.5)], 10, transactional = true)
    balance = MultiSuMSyBalance(sumsy, SUMSY_DEP)
    @test sumsy_assets(balance, SUMSY_DEP) == 2000

    book_sumsy!(balance, SUMSY_DEP, 208000, timestamp = 0)
    @test sumsy_assets(balance, SUMSY_DEP) == 210000
    book_sumsy!(balance, SUMSY_DEP, 100000, timestamp = 5)
    @test sumsy_assets(balance, SUMSY_DEP) == sumsy_assets(balance, SUMSY_DEP, timestamp = 5)
    @test sumsy_assets(balance, SUMSY_DEP) == 296000

    @test EconoSim.calculate_adjustments(balance, SUMSY_DEP, 10) == (1000, 36500)
    @test sumsy_assets(balance, SUMSY_DEP, timestamp = 10) == 260500
end

@testset "SingleSuMSyBalance - demurrage - override SuMSy - non transactional" begin
    sumsy = SuMSy(2000, 50000, [(0, 0.1), (50000, 0.2), (150000, 0.5)], 10, transactional = false)
    balance = MultiSuMSyBalance(sumsy, SUMSY_DEP)

    @test get_dem_free(balance, SUMSY_DEP) == 50000
    @test asset_value(balance, SUMSY_DEP) == 2000
    @test sumsy_assets(balance, SUMSY_DEP, timestamp = 0) == 2000
    
    set_sumsy!(balance,
                SuMSy(1000, 0, 0, 10, seed = 10000, transactional = false),
                SUMSY_DEP,
                reset_balance = true,
                reset_dem_free = true)
    
    @test get_dem_free(balance, SUMSY_DEP) == 0
    @test asset_value(balance, SUMSY_DEP) == 11000
    @test sumsy_assets(balance, SUMSY_DEP, timestamp = 0) == 11000
    @test sumsy_assets(balance, SUMSY_DEP, timestamp = 20) == 13000

    set_sumsy!(balance,
                SuMSy(5000, 1000, 0.1, 10, seed = 0, transactional = false),
                SUMSY_DEP,
                reset_balance = true,
                reset_dem_free = false)
    
    @test get_dem_free(balance, SUMSY_DEP) == 0
    @test asset_value(balance, SUMSY_DEP) == 5000
    @test sumsy_assets(balance, SUMSY_DEP, timestamp = 0) == 5000
    @test sumsy_assets(balance, SUMSY_DEP, timestamp = 20) == 13550

    set_sumsy!(balance,
                SuMSy(3000, 20000, 0.2, 10, seed = 10, transactional = false),
                SUMSY_DEP,
                reset_balance = false,
                reset_dem_free = true)
    
    @test get_dem_free(balance, SUMSY_DEP) == 20000
    @test asset_value(balance, SUMSY_DEP) == 5000
    @test sumsy_assets(balance, SUMSY_DEP, timestamp = 0) == 5000
    @test sumsy_assets(balance, SUMSY_DEP, timestamp = 20) == 11000
end

@testset "MultiSuMSyBalance - demurrage - overrides - transactional" begin
    sumsy = SuMSy(2000, 50000, [(0, 0.1), (50000, 0.2), (150000, 0.5)], 10, transactional = true)
    balance = MultiSuMSyBalance(sumsy, SUMSY_DEP)
    @test sumsy_assets(balance, SUMSY_DEP, timestamp = 0) == 2000
    
    set_sumsy!(balance,
                SuMSy(1000, 0, 0, 10, seed = 10000, transactional = true),
                SUMSY_DEP,
                reset_balance = true,
                reset_dem_free = true)
    
    @test asset_value(balance, SUMSY_DEP) == 11000
    @test sumsy_assets(balance, SUMSY_DEP, timestamp = 10) == 12000
    @test sumsy_assets(balance, SUMSY_DEP, timestamp = 20) == 13000

    set_sumsy!(balance,
                SuMSy(2000, 5000, 0.1, 10, seed = 0, transactional = true),
                SUMSY_DEP,
                reset_balance = false,
                reset_dem_free = true)
    
    @test asset_value(balance, SUMSY_DEP) == 11000
    @test sumsy_assets(balance, SUMSY_DEP, timestamp = 10) == 12400
    @test sumsy_assets(balance, SUMSY_DEP, timestamp = 15) == 13030
    @test sumsy_assets(balance, SUMSY_DEP, timestamp = 20) == 13660
end

@testset "MultiSuMSyBalance inactive" begin
    sumsy = SuMSy(4000, 50000, [(0, 0.1), (50000, 0.2), (150000, 0.5)], 10)
    balance = MultiSuMSyBalance(sumsy, SUMSY_DEP)

    book_asset!(balance, SUMSY_DEP, 210000, set_to_value = true)
    set_sumsy_active!(balance, SUMSY_DEP, false)

    adjust_sumsy_balance!(balance, SUMSY_DEP, 10)
    @test sumsy_assets(balance, SUMSY_DEP, timestamp = 10) == 210000
end

@testset "MultiSuMSyBalance - SuMSy overrides" begin
    sumsy = SuMSy(2000, 50000, [(0, 0.1), (50000, 0.2), (150000, 0.5)], 10)
    balance = MultiSuMSyBalance(sumsy, SUMSY_DEP)

    set_sumsy!(balance, SuMSy(sumsy, seed = 1000), SUMSY_DEP, reset_balance = true, reset_dem_free = true)
    @test sumsy_assets(balance, SUMSY_DEP) == 3000

    set_sumsy!(balance, SuMSy(sumsy, guaranteed_income = 5000), SUMSY_DEP, reset_balance = false, reset_dem_free = false)
    adjust_sumsy_balance!(balance, SUMSY_DEP, 10)
    @test sumsy_assets(balance, SUMSY_DEP) == 8000

    set_sumsy!(balance, SuMSy(sumsy, dem_free = 3000), SUMSY_DEP, reset_balance = false, reset_dem_free = true)
    @test get_dem_free(balance, SUMSY_DEP) == 3000
    @test EconoSim.calculate_adjustments(balance, SUMSY_DEP, 20) == (2000, 500)
    adjust_sumsy_balance!(balance, SUMSY_DEP, 20)
    @test sumsy_assets(balance, SUMSY_DEP) == 9500
end

@testset "MultiSuMSyBalance - demurrage free transfer" begin
    sumsy = SuMSy(2000, 50000, [(0, 0.1), (50000, 0.2), (150000, 0.5)], 10)
    balance1 = MultiSuMSyBalance(sumsy, SUMSY_DEP)
    balance2 = MultiSuMSyBalance(sumsy, SUMSY_DEP)

    transfer_dem_free!(balance1, balance2, SUMSY_DEP, 10000)
    @test get_dem_free(balance1, SUMSY_DEP) == 40000
    @test get_dem_free(balance2, SUMSY_DEP) == 60000
end

@testset "Transfer queues" begin
    e1 = BalanceEntry("E1")
    e2 = BalanceEntry("E2")

    b1 = Balance()
    min_asset!(b1, e1, typemin(Currency))
    min_liability!(b1, e2, typemin(Currency))

    b2 = Balance()
    min_asset!(b2, e1, typemin(Currency))
    min_liability!(b2, e2, typemin(Currency))

    # 1 valid transfer
    queue_asset_transfer!(b1, b2, e1, 100)
    @test execute_transfers!(b1)
    @test length(b1.transfer_queue) == 0
    @test asset_value(b1, e1) == -100
    @test asset_value(b2, e1) == 100

    # 1 valid, 1 invalid transfer
    queue_asset_transfer!(b1, b2, e1, 100)
    queue_liability_transfer!(b1, b2, e1, 100)
    @test !execute_transfers!(b1)
    @test length(b1.transfer_queue) == 0
    @test asset_value(b1, e1) == -100 # value unchanged
    @test asset_value(b2, e1) == 100 # value unchanged
    @test liability_value(b1, e1) == 0
    @test liability_value(b2, e1) == 0

    # Multiple valid transfers
    @test book_asset!(b1, e2, 100)
    @test book_liability!(b2, e1, 100)

    queue_asset_transfer!(b1, b2, e1, 100)
    queue_asset_transfer!(b1, b2, e2, 50)
    queue_asset_transfer!(b1, b2, e2, 25)

    queue_liability_transfer!(b2, b1, e1, 50)
    queue_liability_transfer!(b2, b1, e2, 100)
    queue_liability_transfer!(b2, b1, e2, 25)

    @test execute_transfers!(b1)
    @test length(b1.transfer_queue) == 0
    @test length(b2.transfer_queue) > 0 # Only b1 transfer queue is processed
    @test asset_value(b1, e1) == -200
    @test asset_value(b2, e1) == 200
    @test asset_value(b1, e2) == 25
    @test asset_value(b2, e2) == 75

    @test execute_transfers!(b2)
    @test length(b2.transfer_queue) == 0
    @test liability_value(b1, e1) == 50
    @test liability_value(b2, e1) == 50
    @test liability_value(b1, e2) == 125
    @test liability_value(b2, e2) == -125
end

@testset "Price" begin
    c1 = BalanceEntry("C1")
    c2 = BalanceEntry("C2")

    b1 = Balance()
    min_asset!(b1, c1, typemin(Currency))
    book_asset!(b1, c1, 100)
    book_asset!(b1, c2, 100)
    @test asset_value(b1, c1) == 100
    @test asset_value(b1, c2) == 100

    b2 = Balance()

    p1 = Price([c1 => 50, c2 => 150], c1)
    @test p1[c1] == 50
    @test p1[c2] == 150

    p2 = Price([c1 => 150, c2 => 50], c1)
    @test p2[c1] == 150
    @test p2[c2] == 50

    @test !pay!(b1, b2, p1)
    @test pay!(b1, b2, p2)

    @test asset_value(b1, c1) == -50
    @test asset_value(b1, c2) == 50

    @test asset_value(b2, c1) == 150
    @test asset_value(b2, c2) == 50
end

@testset "Change Currency Precision" begin
    set_currency_precision!(4)

    b = Balance()
    book_asset!(b, BalanceEntry("DEP"), 10)
    @test typeof(asset_value(b, BalanceEntry("DEP"))) == FixedDecimal{Int128, 4}

    set_currency_precision!(6)

    b = Balance()
    book_asset!(b, BalanceEntry("DEP"), 10)
    @test typeof(asset_value(b, BalanceEntry("DEP"))) == FixedDecimal{Int128, 6}
end