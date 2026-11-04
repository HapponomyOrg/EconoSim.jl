using Test
using EconoSim
using Random

# Guaranteed income and demurrage are settled every `granularity` steps. Bookings and transfers settle the elapsed
# granules first, so the outcome must not depend on how often a balance is adjusted.

const TIMING_INTERVAL = 10
const TIMING_END = 100

timing_patterns() = [
    "every step" => collect(1:TIMING_END),
    "on cycle" => collect(TIMING_INTERVAL:TIMING_INTERVAL:TIMING_END),
    "single jump" => [TIMING_END],
    "off cycle" => [25, 30, 55, TIMING_END],
    "every 7 steps" => vcat(collect(7:7:TIMING_END), [TIMING_END]),
    "none" => Int[],
]

timing_sumsys() = [
    "flat" => SuMSy(1000, 0, 0.1),
    "tiers and dem free" => SuMSy(2000, 5000, [(0, 0.01), (5000, 0.05), (20000, 0.1)]; seed = 3000),
]

# Deposits made at fixed moments, independent of the adjustment pattern.
const TIMING_DEPOSITS = Dict(15 => 10000, 47 => -2500, 80 => 777)

function single_run(sumsy, granularity, pattern; deposits = Dict{Int, Int}())
    b = SingleSuMSyBalance(sumsy, sumsy_interval = TIMING_INTERVAL, granularity = granularity, initialize = true)

    for t in sort(unique(vcat(pattern, collect(keys(deposits)))))
        haskey(deposits, t) && book_sumsy!(b, deposits[t], timestamp = t)
        t in pattern && adjust_sumsy_balance!(b, t)
    end

    adjust_sumsy_balance!(b, TIMING_END)

    return asset_value(get_balance(b), SUMSY_DEP)
end

function multi_run(sumsy, granularity, pattern; deposits = Dict{Int, Int}())
    b = MultiSuMSyBalance(sumsy, SUMSY_DEP, sumsy_interval = TIMING_INTERVAL, granularity = granularity)

    for t in sort(unique(vcat(pattern, collect(keys(deposits)))))
        haskey(deposits, t) && book_sumsy!(b, SUMSY_DEP, deposits[t], timestamp = t)
        t in pattern && adjust_sumsy_balance!(b, SUMSY_DEP, t)
    end

    adjust_sumsy_balance!(b, SUMSY_DEP, TIMING_END)

    return asset_value(get_balance(b), SUMSY_DEP)
end

@testset "SuMSy timing - fast demurrage equals calculate_time_range_demurrage" begin
    rng = MersenneTwister(42)
    C = typeof(CUR_0)

    for settings in ([(0, 0.1)], [(0, 0.01), (5000, 0.05), (20000, 0.1)], [(0, 0), (1000, 0.2)]),
            dem_free in (0, 5000), negative in (false, true)
        tiers = make_tiers(settings)
        fast = EconoSim.fast_tiers(tiers, C)

        for _ in 1:200
            balance = Currency(round(rand(rng) * 200000 - 50000, digits = 4))
            interval = rand(rng, 1:365)
            timerange = rand(rng, 1:interval)
            @test EconoSim.fast_time_range_demurrage(balance, fast, Currency(dem_free), interval, timerange, negative) ==
                    calculate_time_range_demurrage(balance, tiers, dem_free, interval, timerange, negative)
        end
    end
end

@testset "SuMSy timing - granularity = period gives the per-period results" begin
    # Reference: the per-period compounding of calculate_timerange_adjustments over 10 periods.
    for (_, sumsy) in timing_sumsys()
        b = SingleSuMSyBalance(sumsy, sumsy_interval = TIMING_INTERVAL, initialize = true)
        gi, dem = calculate_timerange_adjustments(b, TIMING_END, SUMSY_DEP)
        @test single_run(sumsy, TIMING_INTERVAL, last(timing_patterns()[2])) == get_seed(b) + gi - dem
    end

    get_currency_precision(CUR_0) == 4 && @test single_run(SuMSy(1000, 0, 0.1), TIMING_INTERVAL, [TIMING_END]) == 6513.2156
end

@testset "SuMSy timing - no drift" begin
    for (_, sumsy) in timing_sumsys(), granularity in (1, 3, 5, TIMING_INTERVAL), run in (single_run, multi_run)
        reference = run(sumsy, granularity, last(first(timing_patterns())))
        reference_deposits = run(sumsy, granularity, last(first(timing_patterns())), deposits = TIMING_DEPOSITS)

        for (_, pattern) in timing_patterns()
            @test run(sumsy, granularity, pattern) == reference
            @test run(sumsy, granularity, pattern, deposits = TIMING_DEPOSITS) == reference_deposits
        end
    end
end

@testset "SuMSy timing - smaller granularity reduces the end of period advantage" begin
    # 10% demurrage per 30 steps, no income. 10000 held, 9000 paid away at step 29 or at step 1.
    sumsy = SuMSy(0, 0, 0.1)

    function demurrage_paid(granularity, step)
        a = SingleSuMSyBalance(sumsy, sumsy_interval = 30, granularity = granularity)
        b = SingleSuMSyBalance(sumsy, sumsy_interval = 30, granularity = granularity)
        book_asset!(get_balance(a), SUMSY_DEP, 10000)
        transfer_sumsy!(a, b, 9000, timestamp = step)
        adjust_sumsy_balance!(a, 30)

        return 1000 - asset_value(get_balance(a), SUMSY_DEP)
    end

    # Settled once per period: paying late avoids all demurrage on the 9000.
    @test demurrage_paid(30, 1) == demurrage_paid(30, 29) == 100

    # Settled every step: paying late no longer avoids the demurrage on the 9000 for the steps it was held.
    @test demurrage_paid(1, 1) < 130
    @test demurrage_paid(1, 29) > 900
end

@testset "SuMSy timing - yearly parameters, daily settlement" begin
    # Period 365, income 24000, 12% demurrage, settled daily.
    yearly = SuMSy(24000, 0, 0.12)
    b = SingleSuMSyBalance(yearly, sumsy_interval = 365, granularity = 1)
    gi, dem = adjust_sumsy_balance!(b, 365)

    # A full period pays exactly the guaranteed income.
    @test gi == 24000

    # Same as settling a period of 1 with 24000 / 365 and 12% / 365, up to rounding of the daily income.
    daily = SuMSy(24000 / 365, 0, 0.12 / 365)
    d = SingleSuMSyBalance(daily, sumsy_interval = 1)
    d_gi, d_dem = adjust_sumsy_balance!(d, 365)
    @test abs(gi - d_gi) < 0.01
    @test abs(dem - d_dem) < 0.01

    # Daily income alternates between two values one unit apart, e.g. 65.7534 and 65.7535 at 4 decimals.
    b = SingleSuMSyBalance(SuMSy(24000, 0, 0), sumsy_interval = 365, granularity = 1)
    amounts = [first(adjust_sumsy_balance!(b, t)) for t in 1:365]
    @test length(Set(amounts)) == 2
    @test maximum(amounts) - minimum(amounts) < 0.001
    @test sum(amounts) == 24000
end

@testset "SuMSy timing - remainder carries over" begin
    sumsy = SuMSy(1000, 0, 0.1)
    b = SingleSuMSyBalance(sumsy, sumsy_interval = 10)

    @test adjust_sumsy_balance!(b, 15) == (1000, 0)
    @test get_last_adjustment(b) == 10 # The 5 remaining steps carry over.
    @test adjust_sumsy_balance!(b, 19) == (0, 0)
    @test get_last_adjustment(b) == 10
    @test adjust_sumsy_balance!(b, 20) == (1000, 100)
    @test get_last_adjustment(b) == 20
    @test asset_value(get_balance(b), SUMSY_DEP) == 1900

    g = SingleSuMSyBalance(sumsy, sumsy_interval = 10, granularity = 4)
    @test adjust_sumsy_balance!(g, 10) == (800, 16) # Granules 0-4 and 4-8: +400, then +400 - 400 * 0.1 * 4 / 10.
    @test get_last_adjustment(g) == 8
end

@testset "SuMSy timing - set_last_adjustment! restarts the granules" begin
    sumsy = SuMSy(1000, 0, 0.1)
    b = SingleSuMSyBalance(sumsy, sumsy_interval = 10, granularity = 5)

    adjust_sumsy_balance!(b, 5)
    set_last_adjustment!(b, 45)
    @test get_last_adjustment(b) == 45
    @test calculate_adjustments(b, 49) == (0, 0)
    @test calculate_adjustments(b, 50) == (500, 25)
end

@testset "SuMSy timing - inactive balances do not accrue" begin
    sumsy = SuMSy(1000, 0, 0.1)
    b = SingleSuMSyBalance(sumsy, sumsy_interval = 10, granularity = 1, activate = false)

    @test adjust_sumsy_balance!(b, 25) == (0, 0)
    @test get_last_adjustment(b) == 25

    # Accrual starts at 25, not at 0.
    set_sumsy_active!(b, true)
    @test first(calculate_adjustments(b, 35)) == 1000
end

@testset "SuMSy timing - granularity settings" begin
    sumsy = SuMSy(1000, 0, 0.1)
    @test get_granularity(SingleSuMSyBalance(sumsy, sumsy_interval = 10)) == 10
    @test get_granularity(MultiSuMSyBalance(sumsy, SUMSY_DEP, sumsy_interval = 10), SUMSY_DEP) == 10
    @test_throws ArgumentError SingleSuMSyBalance(sumsy, granularity = 0)

    b = SingleSuMSyBalance(sumsy, sumsy_interval = 10)
    set_granularity!(b, 2)
    @test get_granularity(b) == 2
    @test_throws ArgumentError set_granularity!(b, -1)
end

@testset "SuMSy timing - model settles every granule" begin
    sumsy = SuMSy(1000, 0, 0.1)
    model = create_sumsy_model(sumsy_interval = 10, granularity = 2, model_behaviors = process_model_sumsy!)
    actor = add_sumsy_actor!(model, sumsy = sumsy, initialize = false)
    @test get_granularity(get_balance(actor)) == 2

    run_econo_model!(model, 20)

    reference = SingleSuMSyBalance(sumsy, sumsy_interval = 10, granularity = 2)
    adjust_sumsy_balance!(reference, 20)
    @test asset_value(get_balance(get_balance(actor)), SUMSY_DEP) == asset_value(get_balance(reference), SUMSY_DEP)
    @test get_last_adjustment(get_balance(actor)) == 20
end
