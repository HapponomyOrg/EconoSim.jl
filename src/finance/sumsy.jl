using DataStructures

SUMSY_DEP = BalanceEntry("SuMSy deposit")
SUMSY_DEBT = BalanceEntry("SuMSy debt")

DemTiers = Vector{Tuple{Interval, Percentage}}
NO_DEM_TIER = make_tiers([(0, 0)])

"""
    struct SuMSy

Representation of the parameters of a SuMSy implementation.

* guaranteed_income: the periodical guaranteed income.
* dem_free_buffer: the demurrage free buffer which is allocated to all accounts which have a right to a guaranteed income.
* dem_tuples: the demurrage tiers. This is a list of tuples consisting of a lower bound and a demurrage percentage. The demurrage percentage is applied to the amounts above the lower bound up to the the next higher lower bound. If the demurrage free buffer of an account is larger than 0, all bounds are shifted up with this amount and no demurrage is applied to the amount up to the available demurrage free buffer.
The lower bound of the first tuple is always set to 0.
* interval: the size of the period after which the next demurrage is calculated and the next guaranteed income is issued.
* seed: the amount whith which new accounts start.
"""
mutable struct SuMSy
    guaranteed_income::Currency
    dem_free::Currency
    dem_tiers::DemTiers
    interval::Int64
    seed::Currency
    SuMSy(guaranteed_income::Real,
        dem_free::Real,
        dem_tuples::Union{DemTiers, Vector{T}},
        interval::Integer;
        seed::Real = 0) where {T <: Tuple{Real, Real}} = new(guaranteed_income,
                        dem_free,
                        make_tiers(dem_tuples),
                        interval,
                        seed)
end

"""
    SuMSy(guaranteed_income::Real, dem_free_buffer::Real, dem::Percentage)

Create a SuMSy struct with 1 demurrage tier.
"""
function SuMSy(guaranteed_income::Real,
            dem_free::Real,
            dem::Real,
            interval::Integer;
            seed::Real = 0)
    return SuMSy(guaranteed_income, dem_free, [(0, dem)], interval, seed = seed)
end

"""
    make_tiers(dem_tuples::Vector{T}) where  {T <: Tuple{Real, Real}}

Convert the vector of tuples into DemTiers.
The first interval always starts with 0, the last interval always has an unbounded upper bound. Tiers are sorted from low to high.
"""
function make_tiers(dem_tuples::Vector{T}) where  {T <: Tuple{Real, Real}}
    sort!(dem_tuples)
    tiers = DemTiers()
    lower_bound = 0
    demurrage = dem_tuples[1][2]

    if length(dem_tuples) > 1
        upper_bound = 0

        for index in 2:length(dem_tuples)
            tuple = dem_tuples[index]
            upper_bound = tuple[1]

            push!(tiers,
                (Interval{Currency, Open, Closed}(lower_bound, upper_bound),
                demurrage))

            lower_bound = upper_bound
            demurrage = tuple[2]
        end
    end

    push!(tiers,
        (Interval{Currency, Open, Unbounded}(lower_bound, nothing),
        demurrage))

    return tiers
end

make_tiers(dem_tiers::DemTiers) = sort!(dem_tiers)

"""
    set_sumsy_active!(sumsy::SuMSy, balance::Balance, flag::Bool)

Indicate whether the balance participates in SuMSy or not.
"""
function set_sumsy_active!(sumsy::SuMSy, balance::Balance, flag::Bool)
    balance.sumsy_active = flag
end

is_sumsy_active(balance::Balance) = isnothing(balance.sumsy_active) ? true : balance.sumsy_active

function set_sumsy!(sumsy::SuMSy,
                    balance::Balance,
                    seed::Real,
                    guaranteed_income::Real = sumsy.guaranteed_income,
                    dem_free::Real = sumsy.dem_free,
                    dem_tuples::Union{DemTiers, Vector{T}} = sumsy.dem_tiers) where {T <: Tuple{Real, Real}}
    set_seed!(balance, seed)
    set_guaranteed_income!(balance, guaranteed_income)
    set_dem_free!(dem_free)
    set_dem_tiers!(dem_tuples)

    return balance
end

function set_seed!(balance::Balance, seed::Real)
    balance.seed = Currency(seed)
    return balance
end

function get_seed(sumsy::SuMSy, balance::Balance)
    if is_sumsy_active(balance)
        return isnothing(balance.seed) ? sumsy.seed : balance.seed
    else
        return Currency(0)
    end
end

function set_guaranteed_income!(balance, guaranteed_income::Real)
    balance.guaranteed_income = Currency(guaranteed_income)
    return balance
end

function get_guaranteed_income(sumsy::SuMSy, balance::Balance)
    if is_sumsy_active(balance)
        return isnothing(balance.guaranteed_income) ? sumsy.guaranteed_income : balance.guaranteed_income
    else
        return Currency(0)
    end
end

function set_dem_free!(balance, dem_free::Real)
    balance.dem_free = Currency(dem_free)
    return balance
end

"""
    get_dem_free(balance::Balance)

Returns the size of the available demurrage free buffer.
"""
function get_dem_free(sumsy::SuMSy, balance::Balance)
    if is_sumsy_active(balance)
        return balance.dem_free == nothing ? sumsy.dem_free : balance.dem_free
    else
        return Currency(0)
    end
end

"""
    dem_free_transfer!(source::Balance, destination::Balance, amount::Real)

Transfer a part or all of the demurrage free buffer from one balance to another. No more than the available demurrage free buffer can be transferred.
* source::Balance - the balance from which the demurrage free amount is taken.
* destination::Balance - the balance to which the demurrage free buffer is transferred.
* amount::Real - the amount to be transferred.
* return - the actual amount which is transferred. This can be less than the amount passed when the available demurrage free buffer was smaller.
"""
function dem_free_transfer!(source::Balance, destination::Balance, amount::Real)
    transferred = Currency(min(amount, get_dem_free(source)))
    set_dem_free(source, get_dem_free(source) - transferred)
    set_dem_free(detination, get_dem_free(destination) + transferred)

    return transferred
end

function set_dem_tiers!(balance::Balance, dem_tuples::Union{DemTiers, Vector{T}}) where {T <: Tuple{Real, Real}}
    balance.dem_tiers = make_tiers(dem_tuples)
    return balance
end

function get_dem_tiers(sumsy::SuMSy, balance::Balance)
    if is_sumsy_active(balance)
        return isnothing(balance.dem_tiers) ? sumsy.dem_tiers : balance.dem_tiers
    else
        return NO_DEM_TIER
    end
end

function sumsy_balance(balance)
    return asset_value(balance, SUMSY_DEP)
end

"""
    sumsy_transfer(source::Balance, destination::Balance, amount::Float64)

Transfer an amount of SuMSy money from one balance sheet to another. No more than the available amount of money can be transferred.
Negative amounts result in a transfer from destination to source.
"""
function sumsy_transfer!(source::Balance, destination::Balance, amount::Real, timestamp::Int = 0)
    if amount > 0
        amount = min(amount, sumsy_balance(source))
    else
        amount = min(-amount, sumsy_balance(destination))
    end

    transfer_asset!(source, destination, SUMSY_DEP, amount, timestamp)
end

"""
    calculate_demurrage(sumsy::SuMSy, balance::Balance, timestamp::Int64)

Calculates the demurrage due at the current timestamp. This is not restricted to timestamps which correspond to multiples of the SuMSy interval.
"""
function calculate_demurrage(sumsy::SuMSy, balance::Balance, step::Int)
    transactions = balance.transactions
    cur_balance = asset_value(balance, SUMSY_DEP)
    period = mod(step, sumsy.interval) == 0 ? sumsy.interval : mod(step, sumsy.interval)
    period_start = step - period
    weighted_balance = 0
    i = length(transactions)
    t_step = step

    while i > 0 && transactions[i].timestamp >= period_start
        t_step = transactions[i].timestamp
        amount = 0

        while i > 0 && transactions[i].timestamp == t_step
            t = transactions[i]

            for transaction in t.transactions
                if transaction.type == asset && transaction.entry == SUMSY_DEP
                    amount += transaction.amount
                end
            end

            i -= 1
        end

        weighted_balance += (step - t_step) * cur_balance
        step = t_step
        cur_balance -= amount
    end

    if t_step > period_start
        weighted_balance += (t_step - period_start) * cur_balance
    end

    avg_balance = max(weighted_balance / period - get_dem_free(sumsy, balance), 0)

    demurrage = Currency(0)

    for tier in sumsy.dem_tiers
        if avg_balance <= 0
            break
        else
            if is_right_unbounded(tier[1])
                amount = avg_balance
                avg_balance = 0
            else
                amount = min(span(tier[1]), avg_balance)
                avg_balance -= span(tier[1])
            end

            demurrage += amount * tier[2]
        end
    end

    return demurrage
end

"""
    process_ready(sumsy::SuMSy, step::Int)

Check whether processing needs to be done.
"""
process_ready(sumsy::SuMSy, step::Int) = mod(step, sumsy.interval) == 0

"""
    process_sumsy!(sumsy::SuMSy, timestamp::Int64, balance::Balanace)

Processes demurrage and guaranteed income if the timestamp is a multiple of the SuMSy interval. Otherwise this function does nothing. Returns the deposited guaranteed income amount and the subtracted demurrage. When this function is called with timestamp == 0, the balance will be 'seeded'. The seed amount is added to the returned income.

* sumsy: the SuMSy implementation to use for calculations.
* balance: the balance on which to apply SuMSy.
* timestamp: the current timestamp. Used to determine whether action needs to be taken.
"""
function process_sumsy!(sumsy::SuMSy, balance::Balance, step::Int)
    income = 0
    demurrage = 0

    if is_sumsy_active(balance) && process_ready(sumsy, step)
        demurrage = calculate_demurrage(sumsy, balance, step)

        if step == 0
            income += get_seed(sumsy, balance)
            book_asset!(balance, SUMSY_DEP, sumsy.seed, step, comment = "Seed")
        end

        income += sumsy.guaranteed_income
        book_asset!(balance, SUMSY_DEP, sumsy.guaranteed_income, step, comment = "Guaranteed income")

        book_asset!(balance, SUMSY_DEP, -demurrage, step, comment = "Demurrage")
    end

    return income, demurrage
end

function sumsy_loan(creditor::Balance,
            debtor::Balance,
            amount::Real,
            installments::Integer,
            interval = 1,
            timestamp::Int64 = 0;
            interest_rate::Real = 0,
            money_entry::BalanceEntry = SUMSY_DEP,
            debt_entry::BalanceEntry = SUMSY_DEBT)
    return borrow(creditor, debtor, amount, interest_rate, installments, interval, timestamp, bank_loan = false, negative_allowed = false, money_entry = money_entry, debt_entry = debt_entry)
end
