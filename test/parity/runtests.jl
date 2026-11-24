# Primitive parity: main EconoSim vs EconoSimCore.
#
# Both packages are loaded from this repository via path sources in
# `Project.toml`. The comparison is exact: every monetary value is compared as
# its 10^-4 scaled integer, so a difference of one last decimal fails.
#
# Run with:
#   julia --project=test/parity test/parity/runtests.jl

using Test
using Random
import EconoSim
import EconoSimCore

const ES = EconoSim
const EC = EconoSimCore

# EconoSimCore is fixed at four decimal places; main EconoSim is configurable.
ES.set_currency_precision!(4)

legacy_scaled(value) = Int128(getfield(value, :i))
core_scaled(value::EC.Money) = Int128(value.value)

function assert_same_money(legacy, core)
    @test legacy_scaled(legacy) == core_scaled(core)
end

function assert_same_sumsy(legacy_sumsy, core_sumsy)
    @test legacy_scaled(legacy_sumsy.income.guaranteed_income) ==
          core_scaled(core_sumsy.guaranteed_income)
    @test legacy_scaled(legacy_sumsy.demurrage.dem_free) ==
          core_scaled(core_sumsy.dem_free)
    @test length(legacy_sumsy.demurrage.dem_tiers) ==
          length(core_sumsy.demurrage.rates)
end

const FLAT_TIERS = [(0.0, 0.01)]
const PAPER_TIERS = [
    (0.0, 0.01),
    (50_000.0, 0.02),
    (500_000.0, 0.05),
    (1_000_000.0, 0.1),
    (10_000_000.0, 0.5),
    (50_000_000.0, 0.95),
]

@testset "SuMSy parameters and telo" begin
    for tiers in (FLAT_TIERS, PAPER_TIERS)
        legacy_sumsy = ES.SuMSy(2_000, 0, tiers)
        core_sumsy = EC.SuMSy(2_000, 0, tiers)
        assert_same_sumsy(legacy_sumsy, core_sumsy)

        legacy_tiers = ES.make_tiers(tiers)
        core_tiers = EC.make_tiers(tiers)
        for income in (0, 2_000, 20_000, 100_000, 1_000_000, 20_000_000)
            assert_same_money(ES.telo(income, legacy_tiers, 0),
                              EC.telo(EC.money(income), core_tiers,
                                      EC.MONEY_ZERO))
        end
    end

    # Demurrage-free buffer shifts every tier.
    legacy_tiers = ES.make_tiers(PAPER_TIERS)
    core_tiers = EC.make_tiers(PAPER_TIERS)
    for balance in (0, 1_000, 10_000, 100_000, 1_000_000)
        for dem_free in (0, 25_000)
            for allow_negative in (false, true)
                assert_same_money(
                    ES.calculate_time_range_demurrage(
                        balance, legacy_tiers, dem_free, 1, 1, allow_negative),
                    EC.calculate_time_range_demurrage(
                        EC.money(balance), core_tiers, EC.money(dem_free),
                        1, 1, allow_negative))
            end
        end
    end

    # Negative balances and partial intervals.
    for balance in (-1_000, -100_000)
        for allow_negative in (false, true)
            assert_same_money(
                ES.calculate_time_range_demurrage(
                    balance, legacy_tiers, 0, 30, 15, allow_negative),
                EC.calculate_time_range_demurrage(
                    EC.money(balance), core_tiers, EC.MONEY_ZERO,
                    30, 15, allow_negative))
        end
    end
end

@testset "SuMSy deposit trajectory" begin
    legacy_sumsy = ES.SuMSy(2_000, 0, PAPER_TIERS)
    core_sumsy = EC.SuMSy(2_000, 0, PAPER_TIERS)
    for periods in (0, 1, 30, 500)
        assert_same_money(
            ES.calculate_sumsy_deposit(legacy_sumsy, periods, 1_000),
            EC.calculate_sumsy_deposit(core_sumsy, periods, EC.money(1_000)))
    end
    assert_same_money(
        ES.calculate_sumsy_deposit(legacy_sumsy, 500, 1_000, true),
        EC.calculate_sumsy_deposit(core_sumsy, 500, EC.money(1_000);
                                   allow_negative_demurrage = true))
end

function _legacy_account(tiers; transactional = false, gi_eligible = true,
                         interval = 30, dem_free = 0)
    sumsy = ES.SuMSy(2_000, dem_free, tiers)
    account = ES.SingleSuMSyBalance(sumsy; initialize = false,
                                    allow_negative_sumsy = true,
                                    sumsy_interval = interval,
                                    transactional = transactional,
                                    gi_eligible = gi_eligible)
    ES.book_asset!(account, ES.SUMSY_DEP, 1_000)
    return account
end

function _core_account(tiers; transactional = false, gi_eligible = true,
                       interval = 30, dem_free = 0)
    sumsy = EC.SuMSy(2_000, dem_free, tiers)
    account = EC.SuMSyAccount(sumsy; interval = interval,
                              transactional = transactional,
                              gi_eligible = gi_eligible,
                              dem_free = EC.money(dem_free),
                              allow_negative = true)
    EC.book_asset!(account.balance, EC.SUMSY_DEPOSIT, EC.money(1_000))
    return account
end

function _assert_account(legacy, core)
    @test legacy_scaled(ES.asset_value(legacy, ES.SUMSY_DEP)) ==
          core_scaled(EC.asset_value(core))
end

@testset "SuMSy account adjustments" begin
    for tiers in (FLAT_TIERS, PAPER_TIERS)
        legacy = _legacy_account(tiers)
        core = _core_account(tiers)
        for timestamp in (30, 60, 90, 120)
            legacy_gi, legacy_dem = ES.adjust_sumsy_balance!(legacy, timestamp)
            core_gi, core_dem = EC.adjust!(core, timestamp)
            assert_same_money(legacy_gi, core_gi)
            assert_same_money(legacy_dem, core_dem)
            _assert_account(legacy, core)
        end
    end

    # Legacy skips a partial interval and advances the adjustment clock.
    legacy = _legacy_account(PAPER_TIERS)
    core = _core_account(PAPER_TIERS)
    for timestamp in (30, 75, 90, 100)
        legacy_gi, legacy_dem = ES.adjust_sumsy_balance!(legacy, timestamp)
        core_gi, core_dem = EC.adjust!(core, timestamp)
        assert_same_money(legacy_gi, core_gi)
        assert_same_money(legacy_dem, core_dem)
        _assert_account(legacy, core)
    end

    # Transactional accounts prorate partial periods.
    legacy = _legacy_account(PAPER_TIERS; transactional = true)
    core = _core_account(PAPER_TIERS; transactional = true)
    for timestamp in (15, 30, 45, 75)
        legacy_gi, legacy_dem = ES.adjust_sumsy_balance!(legacy, timestamp)
        core_gi, core_dem = EC.adjust!(core, timestamp)
        assert_same_money(legacy_gi, core_gi)
        assert_same_money(legacy_dem, core_dem)
        _assert_account(legacy, core)
    end

    # GI-ineligible accounts receive no guaranteed income.
    legacy = _legacy_account(PAPER_TIERS; gi_eligible = false)
    core = _core_account(PAPER_TIERS; gi_eligible = false)
    for timestamp in (30, 60)
        legacy_gi, legacy_dem = ES.adjust_sumsy_balance!(legacy, timestamp)
        core_gi, core_dem = EC.adjust!(core, timestamp)
        assert_same_money(legacy_gi, core_gi)
        assert_same_money(legacy_dem, core_dem)
        _assert_account(legacy, core)
    end

    # Demurrage-free buffer.
    legacy = _legacy_account(PAPER_TIERS; dem_free = 25_000)
    core = _core_account(PAPER_TIERS; dem_free = 25_000)
    for timestamp in (30, 60)
        legacy_gi, legacy_dem = ES.adjust_sumsy_balance!(legacy, timestamp)
        core_gi, core_dem = EC.adjust!(core, timestamp)
        assert_same_money(legacy_gi, core_gi)
        assert_same_money(legacy_dem, core_dem)
        _assert_account(legacy, core)
    end
end

@testset "Demurrage tie sweep" begin
    legacy_tiers = ES.make_tiers(PAPER_TIERS)
    core_tiers = EC.make_tiers(PAPER_TIERS)

    function same_demurrage(balance, interval, timerange)
        assert_same_money(
            ES.calculate_time_range_demurrage(
                ES.Currency(balance) / 10_000, legacy_tiers, 0,
                interval, timerange, false),
            EC.calculate_time_range_demurrage(
                EC.Money(balance), core_tiers, EC.MONEY_ZERO,
                interval, timerange, false))
    end

    # Half-unit ties decide the last decimal; sweep them densely.
    for balance in 0:20_000
        same_demurrage(balance, 1, 1)
    end
    for (threshold, _) in PAPER_TIERS
        start = round(Int, threshold * 10_000)
        for balance in max(start - 200, 0):(start + 200)
            same_demurrage(balance, 1, 1)
            same_demurrage(balance, 30, 30)
            same_demurrage(balance, 30, 7)
        end
    end

    rng = MersenneTwister(11)
    for _ in 1:5_000
        same_demurrage(rand(rng, 0:10^12), 30, rand(rng, 1:30))
    end
end

@testset "SuMSy prorating and compounding" begin
    # Legacy compounds full intervals and rounds guaranteed income when the
    # timerange is not a multiple of the interval.
    for tiers in (FLAT_TIERS, PAPER_TIERS)
        legacy = _legacy_account(tiers; transactional = true, interval = 30)
        core = _core_account(tiers; transactional = true, interval = 30)
        for timestamp in (1, 3, 7, 13, 29, 30, 37, 44, 60, 61, 91, 137)
            legacy_gi, legacy_dem = ES.adjust_sumsy_balance!(legacy, timestamp)
            core_gi, core_dem = EC.adjust!(core, timestamp)
            assert_same_money(legacy_gi, core_gi)
            assert_same_money(legacy_dem, core_dem)
            _assert_account(legacy, core)
        end
    end
end

@testset "Balance booking" begin
    legacy = ES.Balance()
    core = EC.Balance()

    @test ES.book_asset!(legacy, ES.DEPOSIT, 100)
    @test EC.book_asset!(core, EC.DEPOSIT, EC.money(100))
    @test ES.book_liability!(legacy, ES.DEBT, 40)
    @test EC.book_liability!(core, EC.DEBT, EC.money(40))

    assert_same_money(ES.asset_value(legacy, ES.DEPOSIT),
                      EC.asset_value(core, EC.DEPOSIT))
    assert_same_money(ES.liability_value(legacy, ES.DEBT),
                      EC.liability_value(core, EC.DEBT))
    assert_same_money(ES.equity(legacy), EC.equity(core))
    assert_same_money(ES.assets_value(legacy), EC.assets_value(core))
    assert_same_money(ES.liabilities_value(legacy), EC.liabilities_value(core))
    @test ES.validate(legacy) == EC.validate(core) == true

    # Transfers.
    legacy_other = ES.Balance()
    core_other = EC.Balance()
    @test ES.transfer_asset!(legacy, legacy_other, ES.DEPOSIT, 25)
    @test EC.transfer_asset!(core, core_other, EC.DEPOSIT, EC.money(25))
    assert_same_money(ES.asset_value(legacy, ES.DEPOSIT),
                      EC.asset_value(core, EC.DEPOSIT))
    assert_same_money(ES.asset_value(legacy_other, ES.DEPOSIT),
                      EC.asset_value(core_other, EC.DEPOSIT))

    # Minimum balance rejection leaves both sides unchanged.
    ES.min_asset!(legacy_other, ES.DEPOSIT, 20)
    EC.min_asset!(core_other, EC.DEPOSIT, EC.money(20))
    @test ES.transfer_asset!(legacy_other, legacy, ES.DEPOSIT, 10) == false
    @test EC.transfer_asset!(core_other, core, EC.DEPOSIT,
                             EC.money(10)) == false
    assert_same_money(ES.asset_value(legacy, ES.DEPOSIT),
                      EC.asset_value(core, EC.DEPOSIT))
    assert_same_money(ES.asset_value(legacy_other, ES.DEPOSIT),
                      EC.asset_value(core_other, EC.DEPOSIT))

    ES.clear!(legacy)
    EC.clear!(core)
    assert_same_money(ES.assets_value(legacy), EC.assets_value(core))
    assert_same_money(ES.liabilities_value(legacy), EC.liabilities_value(core))
end

function _run_debt(rate, installments; bank_loan = true, amount = 1_000,
                   creditor_deposit = 0, endowment = 0,
                   expect_settled = true)
    legacy_creditor = ES.Balance()
    legacy_debtor = ES.Balance()
    core_creditor = EC.Balance()
    core_debtor = EC.Balance()

    if creditor_deposit > 0
        ES.book_asset!(legacy_creditor, ES.DEPOSIT, creditor_deposit)
        EC.book_asset!(core_creditor, EC.DEPOSIT, EC.money(creditor_deposit))
    end

    legacy_debt = ES.borrow(legacy_creditor, legacy_debtor, amount, rate,
                            installments; bank_loan = bank_loan)
    core_debt = EC.borrow(core_creditor, core_debtor, EC.money(amount), rate,
                          installments; bank_loan = bank_loan)

    if endowment > 0
        ES.book_asset!(legacy_debtor, ES.DEPOSIT, endowment)
        EC.book_asset!(core_debtor, EC.DEPOSIT, EC.money(endowment))
    end

    @test length(legacy_debt.installments) == length(core_debt.installments)
    for index in eachindex(legacy_debt.installments)
        assert_same_money(legacy_debt.installments[index],
                          core_debt.installments[index])
    end

    steps = expect_settled ? max(20 * installments, 100) : installments
    for _ in 1:steps
        ES.debt_settled(legacy_debt) && EC.debt_settled(core_debt) && break
        legacy_debt, legacy_paid = ES.process_debt!(legacy_debt)
        core_debt, core_paid = EC.process_debt!(core_debt)
        for index in 1:3
            assert_same_money(legacy_paid[index], core_paid[index])
        end
        @test ES.debt_settled(legacy_debt) == EC.debt_settled(core_debt)
    end

    @test ES.debt_settled(legacy_debt) == EC.debt_settled(core_debt)
    if expect_settled
        @test ES.debt_settled(legacy_debt) == true
    end
    assert_same_money(ES.assets_value(legacy_debtor),
                      EC.assets_value(core_debtor))
    assert_same_money(ES.liabilities_value(legacy_debtor),
                      EC.liabilities_value(core_debtor))
    assert_same_money(ES.assets_value(legacy_creditor),
                      EC.assets_value(core_creditor))
    assert_same_money(ES.liabilities_value(legacy_creditor),
                      EC.liabilities_value(core_creditor))
end

@testset "Debt lifecycle" begin
    for rate in (0.15, 0.0123, 0.0014)
        _run_debt(rate, 10; endowment = 2_000)
    end
    _run_debt(0.15, 1; endowment = 1_000)
    _run_debt(0.15, 5; amount = 500, endowment = 1_000)
    _run_debt(0.15, 10; bank_loan = false, creditor_deposit = 1_000,
              endowment = 2_000)

    # No income: both implementations spread the shortfall identically.
    _run_debt(0.15, 10; endowment = 0, expect_settled = false)
end
