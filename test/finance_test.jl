using Test
using EconoSim
using Intervals

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

@testset "Transactions" begin
    b1 = Balance()
    b2 = Balance()
    a = BalanceEntry("Asset")

    book_asset!(b1, a, 100, comment = "book")
    transfer_asset!(b1, b2, a, 50, comment = "transfer")

    @test length(b1.transactions) == 2
    @test b1.transactions[1].timestamp == 0
    @test b1.transactions[1].transactions[1].type == asset
    @test b1.transactions[1].transactions[1].entry == a
    @test b1.transactions[1].transactions[1].amount == 100
    @test b1.transactions[1].transactions[1].comment == "book"
    @test b1.transactions[2].timestamp == 0
    @test b1.transactions[2].transactions[1].type == asset
    @test b1.transactions[2].transactions[1].entry == a
    @test b1.transactions[2].transactions[1].amount == -50
    @test b1.transactions[2].transactions[1].comment == "transfer"

    @test length(b2.transactions) == 1
    @test b2.transactions[1].timestamp == 0
    @test b2.transactions[1].transactions[1].type == asset
    @test b2.transactions[1].transactions[1].entry == a
    @test b2.transactions[1].transactions[1].amount == 50
    @test b2.transactions[1].transactions[1].comment == "transfer"
end

@testset "SuMSy dem tiers" begin
    tiers = EconoSim.make_tiers([(0, 0.1), (10, 0.2), (20, 0.3)])
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

    tiers = EconoSim.make_tiers([(0, 0.1), (10, 0.2)])
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

    tiers = EconoSim.make_tiers([(0, 0.1)])
    @test length(tiers) == 1
    @test first(tiers[1][1]) == 0
    @test last(tiers[1][1]) === nothing
    @test is_left_open(tiers[1][1])
    @test is_right_unbounded(tiers[1][1])
    @test tiers[1][2] == 0.1
end

@testset "SuMSy demurrage - single" begin
    balance = Balance()
    sumsy = SuMSy(2000, 25000, 0.1, 30, seed = 5000)
    process_sumsy!(balance, sumsy, 0)

    @test sumsy_balance(balance, sumsy) == 7000

    book_asset!(balance, SUMSY_DEP, 93000)
    @test calculate_demurrage(balance, sumsy, 30) == 7500

    # Test correct calculation of average weighted balance.
    book_asset!(balance, SUMSY_DEP, 10000, 15)
    @test sumsy_balance(balance, sumsy) == 110000
    @test calculate_demurrage(balance, sumsy, 30) == 8000

    process_sumsy!(balance, sumsy, 30)
    @test sumsy_balance(balance, sumsy) == 104000
end

@testset "SuMSY demurrage - multiple asset bookings" begin
    balance = Balance()
    sumsy = SuMSy(2000, 0, 0.1, 30)

    book_asset!(balance, SUMSY_DEP, 3000, 0)
    book_asset!(balance, SUMSY_DEP, 3000, 10)
    book_asset!(balance, SUMSY_DEP, 3000, 20)

    @test sumsy_balance(balance, sumsy) == 9000
    @test calculate_demurrage(balance, sumsy, 30) == 600

    process_sumsy!(balance, sumsy, 30)
    @test sumsy_balance(balance, sumsy) == 10400
end

@testset "SuMSy demurrage - tiers" begin
    sumsy = SuMSy(2000, 50000, [(0, 0.1), (50000, 0.2), (150000, 0.5)], 10)
    balance = Balance()

    book_asset!(balance, SUMSY_DEP, 210000, 0)

    @test get_dem_free(balance, sumsy) == 50000
    @test calculate_demurrage(balance, sumsy, 10) == 30000

    process_sumsy!(balance, sumsy, 10)
    @test sumsy_balance(balance, sumsy) == 182000
end

@testset "SuMSy inactive" begin
    sumsy = SuMSy(2000, 50000, [(0, 0.1), (50000, 0.2), (150000, 0.5)], 10)
    balance = Balance()

    book_asset!(balance, SUMSY_DEP, 210000, 0)
    set_sumsy_active!(balance, sumsy, false)

    process_sumsy!(balance, sumsy, 10)
    @test sumsy_balance(balance, sumsy) == 210000
end

@testset "SuMSy overrides" begin
    sumsy = SuMSy(2000, 50000, [(0, 0.1), (50000, 0.2), (150000, 0.5)], 10)
    balance = Balance()

    set_seed!(balance, sumsy, 1000)
    process_sumsy!(balance, sumsy, 0)
    @test sumsy_balance(balance, sumsy) == 3000

    set_guaranteed_income!(balance, sumsy, 5000)
    process_sumsy!(balance, sumsy, 10)
    @test sumsy_balance(balance, sumsy) == 8000

    set_initial_dem_free!(balance, sumsy, 3000)
    @test get_dem_free(balance, sumsy) == 3000
    @test calculate_demurrage(balance, sumsy, 20) == 500
    process_sumsy!(balance, sumsy, 20)
    @test sumsy_balance(balance, sumsy) == 12500
end

@testset "SuMSy demurrage free transfer" begin
    sumsy = SuMSy(2000, 50000, [(0, 0.1), (50000, 0.2), (150000, 0.5)], 10)
    balance1 = Balance()
    balance2 = Balance()

    transfer_dem_free!(balance1, balance2, sumsy, 10000)
    @test get_dem_free(balance1, sumsy) == 40000
    @test get_dem_free(balance2, sumsy) == 60000
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

    b2 = Balance()

    p1 = Price([c1 => 50, c2 => 150])
    @test p1[c1] == 50
    @test p1[c2] == 150

    p2 = Price([c1 => 150, c2 => 50])

    @test !pay!(b1, b2, p1)
    @test pay!(b1, b2, p2)

    @test asset_value(b1, c1) == -50
    @test asset_value(b1, c2) == 50

    @test asset_value(b2, c1) == 150
    @test asset_value(b2, c2) == 50
end
