using Test
using EconoSimCore

@testset "EconoSimCore" begin
    @testset "Money" begin
        @test money(1.2345) == scaled(12_345)
        @test money(2) == scaled(20_000)
        @test currency(money(2.5)) == 2.5
        @test Float64(money(2.5)) == 2.5
        @test zero(Money) == scaled(0)
        @test typemin(Money) == Money(typemin(Int64))
        @test typemax(Money) == Money(typemax(Int64))
        @test money(-1.5) + money(1.5) == zero(Money)
        @test abs(money(-1.5)) == money(1.5)
        @test sign(money(-1.5)) == -1

        @test ppm(0.01) == 10_000
        @test ppm(0.5) == 500_000
        @test rate(10_000) == 0.01

        @test apply_rate(money(1_000), ppm(0.01)) == money(10)
        @test apply_rate(money(1_000), ppm(0.20)) == money(200)
        @test apply_rate(money(-1_000), ppm(0.01)) == scaled(-99_999)

        share, remainder = split_amount(money(10), 3)
        @test share == scaled(33_333)
        @test remainder == scaled(1)
        @test share * 3 + remainder == money(10)
    end

    @testset "Rng" begin
        a = Rng(42)
        b = Rng(42)
        @test [next_u64!(a) for _ in 1:5] == [next_u64!(b) for _ in 1:5]

        rng = Rng(7)
        @test all(1 <= rand_index(rng, 10) <= 10 for _ in 1:100)
        @test all(0.0 <= rand_unit(rng) < 1.0 for _ in 1:100)
        @test Rng(0).state != 0
    end

    @testset "Balance" begin
        balance = Balance()
        @test validate(balance)
        @test equity(balance) == zero(Money)

        @test book_asset!(balance, SUMSY_DEPOSIT, money(100))
        @test asset_value(balance, SUMSY_DEPOSIT) == money(100)
        @test equity(balance) == money(100)
        @test validate(balance)

        @test !book_asset!(balance, SUMSY_DEPOSIT, money(-200))
        @test asset_value(balance, SUMSY_DEPOSIT) == money(100)

        @test book_liability!(balance, DEBT, money(40))
        @test liability_value(balance, DEBT) == money(40)
        @test equity(balance) == money(60)
        @test validate(balance)

        @test book_asset!(balance, SUMSY_DEPOSIT, money(-60))
        @test asset_value(balance, SUMSY_DEPOSIT) == money(40)
        @test equity(balance) == zero(Money)
        @test validate(balance)

        other = Balance()
        @test transfer_asset!(balance, other, SUMSY_DEPOSIT, money(15))
        @test asset_value(balance, SUMSY_DEPOSIT) == money(25)
        @test asset_value(other, SUMSY_DEPOSIT) == money(15)
        @test validate(balance)
        @test validate(other)

        @test !transfer_asset!(balance, other, SUMSY_DEPOSIT, money(100))
        @test asset_value(balance, SUMSY_DEPOSIT) == money(25)
        @test asset_value(other, SUMSY_DEPOSIT) == money(15)
    end

    @testset "SuMSy tiers and telo" begin
        flat = make_tiers(0.01)
        @test length(flat.spans) == 1
        @test flat.spans[1] == typemax(Money)
        @test flat.rates[1] == ppm(0.01)

        @test telo(money(2_000), flat) == money(200_000)
        @test telo(2_000.0, 0.01) == money(200_000)
        @test telo(2_000.0, 0.01, 25_000.0) == money(225_000)

        tiers = [
            (0.0, 0.01),
            (50_000.0, 0.02),
            (500_000.0, 0.05),
            (1_000_000.0, 0.10),
            (10_000_000.0, 0.50),
            (50_000_000.0, 0.95),
        ]
        tiered = make_tiers(tiers)
        @test length(tiered.spans) == 6
        @test tiered.spans[1] == money(50_000)
        @test tiered.spans[2] == money(450_000)
        @test tiered.spans[end] == typemax(Money)

        @test telo(200_000.0, tiers) == money(2_655_000)
        @test telo(2_000.0, tiers) == money(125_000)
        @test telo(1_600.0, tiers) * 125 == money(13_125_000)
    end

    @testset "Demurrage" begin
        flat = make_tiers(0.01)
        @test calculate_time_range_demurrage(money(200_000), flat, money(0), 1, 1, false) ==
              money(2_000)
        @test calculate_time_range_demurrage(money(225_000), flat, money(25_000), 1, 1, false) ==
              money(2_000)
        @test calculate_time_range_demurrage(money(200_000), flat, money(0), 30, 30, false) ==
              money(2_000)
        @test calculate_time_range_demurrage(money(0), flat, money(0), 1, 1, false) ==
              money(0)
        @test calculate_time_range_demurrage(money(-100), flat, money(0), 1, 1, false) ==
              money(0)

        tiers = [
            (0.0, 0.01),
            (50_000.0, 0.02),
            (500_000.0, 0.05),
        ]
        tiered = make_tiers(tiers)
        @test calculate_time_range_demurrage(money(60_000), tiered, money(0), 1, 1, false) ==
              money(700)
    end

    @testset "Debt" begin
        bank = Balance()
        debtor = Balance()

        debt = borrow(bank, debtor, money(1_000), 0.01, 4)
        @test length(debt.installments) == 4
        @test sum(debt.installments) == money(1_000)
        @test asset_value(bank, DEBT) == money(1_000)
        @test liability_value(bank, DEPOSIT) == money(1_000)
        @test asset_value(debtor, DEPOSIT) == money(1_000)
        @test liability_value(debtor, DEBT) == money(1_000)
        @test validate(bank)
        @test validate(debtor)

        debt, (paid, interest, shortfall) = process_debt!(debt)
        @test paid == money(250)
        @test interest == money(10)
        @test shortfall == zero(Money)
        @test length(debt.installments) == 3
        @test asset_value(debtor, DEPOSIT) == money(740)
        @test liability_value(debtor, DEBT) == money(750)
        @test validate(bank)
        @test validate(debtor)
    end

    @testset "SuMSy account" begin
        sumsy = SuMSy(2_000.0, 0.0, 0.01)
        account = SuMSyAccount(sumsy; interval = 30)

        guaranteed, demurrage = adjust!(account, 30)
        @test guaranteed == money(2_000)
        @test demurrage == money(0)
        @test asset_value(account) == money(2_000)

        guaranteed, demurrage = adjust!(account, 60)
        @test guaranteed == money(2_000)
        @test demurrage == money(20)
        @test asset_value(account) == money(3_980)

        @test adjust!(account, 60) == (zero(Money), zero(Money))

        deposit = calculate_sumsy_deposit(sumsy, 1_000)
        @test isapprox(currency(deposit), 200_000.0; rtol = 1e-4)
    end
end
