using DataStructures

SUMSY_DEP = BalanceEntry("SuMSy deposit")
SUMSY_DEBT = BalanceEntry("SuMSy debt")

"""
    struct SuMSy

Representation of the parameters of a SuMSy implementation.

* guaranteed_income: the periodical guaranteed income.
* dem_free_buffer: the demurrage free buffer which is allocated to all accounts which have a right to a guaranteed income.
* dem_tiers: the demurrage tiers. This is a list of tuples consisting of an upper bound and a demurrage percantage. The demurrage percentage is applied to the amounts below the upper bound down to the the next lower upper bound. If the demurrage free buffer of an account is larger than 0, all bounds are shifted up with this amount and no demurrage is applied to the amount up to the available demurrage free buffer.
* interval: the size of the period after which the next demurrage is calculated and the next guaranteed income is issued.
* seed: the amount whith which new accounts start.
"""
mutable struct SuMSy
    guaranteed_income::Float64
    dem_free::Float64
    dem_tiers::Vector{Tuple{Float64, Percentage}}
    interval::Int64
    seed::Float64
    SuMSy(guaranteed_income::Real,
        dem_free::Real,
        dem_tiers::Vector{T},
        interval::Integer;
        seed::Real = 0) where {T <: Tuple{Real, Real}} = new(guaranteed_income,
                        dem_free,
                        complete_tiers(dem_tiers),
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
    Make sure there is at least 1 demurrage tier and that the lowest demurrage tier starts at 0.
"""
function complete_tiers(dem_tiers::Vector{T}) where  {T <: Tuple{Real, Real}}
    dem_tiers = Vector{Tuple{Float64, Percentage}}(dem_tiers)
    sort!(dem_tiers, rev = true)

    if isempty(dem_tiers)
        push!(dem_tiers, (0, 0))
    else
        dem_tiers[end] = (0, dem_tiers[end][2])
    end

    return dem_tiers
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

    while i > 0 && transactions[i][1] >= period_start
        t_step = transactions[i][1]
        amount = 0

        while i > 0 && transactions[i][1] == t_step
            t = transactions[i]

            if t[2] == asset && t[3] == SUMSY_DEP
                amount += t[4]
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

    avg_balance = max(weighted_balance / period - dem_free(balance), 0)

    demurrage = 0

    for tier in sumsy.dem_tiers
        amount = max(0, avg_balance - tier[1])
        avg_balance = min(avg_balance, tier[1])
        demurrage += round(amount * tier[2], digits = 2)
    end

    return demurrage
end

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

    if mod(step, sumsy.interval) == 0
        demurrage = calculate_demurrage(sumsy, balance, step)

        if has_guaranteed_income(balance)
            if step == 0
                income += sumsy.seed
                book_asset!(balance, SUMSY_DEP, sumsy.seed, step, comment = "Seed")
            end

            income += sumsy.guaranteed_income
            book_asset!(balance, SUMSY_DEP, sumsy.guaranteed_income, step, comment = "Guaranteed income")
        end

        book_asset!(balance, SUMSY_DEP, -demurrage, step, comment = "Demurrage")
    end

    return income, demurrage
end

function sumsy_balance(balance)
    return asset_value(balance, SUMSY_DEP)
end

"""
    set_guaranteed_income(sumsy::SuMSy, balance::Balance, flag::Bool)

Indicate whether a balance is ellegible to receive a guaranteed income or not. If this is set to true, a demurrage free amount, equal to what is defined in the SuMSy struct, is also assigned to the balance, otherwise the demurrage free buffer is set to 0.
"""
function set_guaranteed_income!(sumsy::SuMSy, balance::Balance, flag::Bool)
    balance.guaranteed_income = flag

    if flag
        balance.dem_free = sumsy.dem_free
    else
        balance.dem_free = 0
    end

    return balance
end

"""
    has_guaranteed_income(balance::Balance)

Returns whether or not the balance is ellegible to receive a guaranteed income.
"""
has_guaranteed_income(balance::Balance) = balance.guaranteed_income == nothing ? false : balance.guaranteed_income

"""
    dem_free(balance::Balance)

Returns the size of the available demurrage free buffer.
"""
dem_free(balance::Balance) = balance.dem_free == nothing ? 0 : balance.dem_free

"""
    sumsy_transfer(source::Balance, destination::Balance, amount::Float64)

Transfer an amount of SuMSy money from one balance sheet to another. No more than the available amount of money can e transferred.
"""
function sumsy_transfer!(source::Balance, destination::Balance, amount::Real, timestamp::Int = 0)
    amount = max(0, min(amount, asset_value(source, SUMSY_DEP)))
    transfer_asset!(source, destination, SUMSY_DEP, amount, timestamp)
end

"""
    dem_free_transfer(source::Balance, destination::Balance, amount::Real)

Transfer a part or all of the demurrage free buffer from one balance to another. No more than the available demurrage free buffer can be transferred.
* source::Balance - the balance from which the demurrage free amount is taken.
* destination::Balance - the balance to which the demurrage free buffer is transferred.
* amount::Real - the amount to be transferred.
* return - the actual amount which is transferred. This can be less than the amount passed when the available demurrage free buffer was smaller.
"""
function dem_free_transfer(source::Balance, destination::Balance, amount::Real)
    transferred = Float64(min(amount, dem_free(source)))
    source.dem_free = dem_free(source) - transferred
    detination.dem_free = dem_free(destination) + transferred

    return transferred
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
