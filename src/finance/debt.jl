using UUIDs

DEPOSIT = BalanceEntry("Deposit")
DEBT = BalanceEntry("Debt")

"""
    mutable struct Debt

A transferable debt contract between two balance sheets.

* id: The unique id of the contract
* creditor: the balance sheet which receives debt payments.
* debtor: the balance sheet from which payments are deducted.
* installments: a list of installments to be paid.
* interest_rate: the interest rate on the debt.
* bank_debt: indicates whether the debt is to a bank. This has an impact on how the initial transfer of money and the downpayments are booked to the creditor's balance sheet.
* money_entry: the entry to be used to book the borrowed money.
* debt_entry: the entry to be used to book the debt.
* creation: the timestamp of the creation of the debt.
* interval: the interval between installments. This can be 0.
* rest_interest: unpaid interest that is not compounded.
* capitalised_interest: the part of the remaining installments that is compounded interest. A bank never created this
    money, so when it is repaid the bank keeps it instead of destroying it.
"""
mutable struct Debt{C <: FixedDecimal}
    id::UUID
    creditor::Balance
    debtor::Balance
    installments::Vector{C}
    interest_rate::Float64
    bank_debt::Bool
    money_entry::BalanceEntry
    debt_entry::BalanceEntry
    creation::Int64
    interval::Int64
    compounded_interest::Bool
    rest_interest::C
    capitalised_interest::C
    Debt(creditor::Balance,
        debtor::Balance,
        installments::Vector{<:Real},
        interest_rate::Real = 0;
        bank_debt::Bool = true,
        money_entry::BalanceEntry = DEPOSIT,
        debt_entry::BalanceEntry = DEBT,
        creation::Int64 = 0,
        interval = 0,
        compounded_interest::Bool = false) = new{Currency}(uuid4(),
            creditor,
            debtor,
            installments,
            interest_rate,
            bank_debt,
            money_entry,
            debt_entry,
            creation,
            interval,
            compounded_interest,
            CUR_0,
            CUR_0)
end

"""
    split_down(total::FixedDecimal, n::Integer)

Split `total` into `n` equal parts rounded down to the currency unit. Returns `(part, leftover)` with
`part * n + leftover == total` and a leftover of 0 up to n - 1 units. Rounding to the nearest unit instead can give a
negative leftover, which made a tiny loan's first installment negative so that its last payments could not be booked.
"""
function split_down(total::FixedDecimal{T, f}, n::Integer) where {T, f}
    part = reinterpret(FixedDecimal{T, f}, fld(total.i, T(n)))

    return part, total - part * n
end

"""
    Debt(creditor::Balance,
        debtor::Balance,
        amount::Real,
        interest_rate::Real,
        installments::Integer;
        bank_debt::Bool = true,
        money_entry::BalanceEntry = DEPOSIT,
        debt_entry::BalanceEntry = DEBT,
        creation::Int64 = 0,
        interval::Int64 = 0)

Create a debt contract between two balances with a number of equal installments. Installments are rounded down to the
currency unit; the leftover goes into the first installment, which is paid last, so no installment is negative.

* creditor: the balance sheet receiving the installments.
* debtor: the balance sheet from which the installments will be subtracted.
* interest_rate: the interest rate on the debt.
* installments: the number of installments.
* bank_debt: whether or not the creditor is a bank.
* money_entry: the balance sheet entry to be used to book the borrowed money.
* debt_entry: the balance sheet entry to be used to book the debt.
"""
function Debt(creditor::Balance,
            debtor::Balance,
            amount::Real,
            interest_rate::Real,
            installments::Integer;
            bank_debt::Bool = true,
            money_entry::BalanceEntry = DEPOSIT,
            debt_entry::BalanceEntry = DEBT,
            creation::Int64 = 0,
            interval::Int64 = 0,
            compounded_interest::Bool = false)
    installment, rest = split_down(Currency(amount), installments)
    installment_vector = fill(installment, (installments))

    # Make sure the entire debt is paid off. The leftover is never negative.
    installment_vector[1] = installment + rest

    return Debt(creditor, debtor, installment_vector, interest_rate; bank_debt = bank_debt, money_entry = money_entry, debt_entry = debt_entry, creation = creation, interval = interval, compounded_interest = compounded_interest)
end

"""
    borrow(creditor::Balance,
        debtor::Balance,
        amount::Real,
        interest_rate::Real,
        installments::Integer,
        timestamp::Int64 = 0;
        bank_loan::Bool = true,
        money_entry::BalanceEntry = DEPOSIT,
        debt_entry::BalanceEntry = DEBT,
        negative_allowed::Bool = true)

Create a debt contract between 2 balance sheets and adjust the balance sheets according to the parameters of the debt contract.

* creditor: the balance sheet receiving the installments.
* debtor: the balance sheet from which the installments will be subtracted.
* amount: the amount to be borrowed.
* interest_rate: the interest rate on the debt.
* installments: the number of installments.
* interval: the interval between the installments.
* timestamp: the current timestamp.
* bank_loan: indicates whether the creditor is a bank. If this is true new money is created to supply the money to the debtor. If this is false, money is transferred from the creditor to the debtor.
* negative_allowed: When this is true, a debtor can lend out money even when it would result in the creditor's money entry becoming negative. Otherwise only the amount available will be lent out. In case of bank loans this is ignored.
* money_entry: the balance sheet entry to be used to book the borrowed money.
* debt_entry: the balance sheet entry to be used to book the debt.
"""
function borrow(creditor::Balance,
            debtor::Balance,
            amount::Real,
            interest_rate::Real,
            installments::Integer,
            interval = 1,
            timestamp::Int64 = 0;
            bank_loan::Bool = true,
            negative_allowed::Bool = true,
            money_entry::BalanceEntry = DEPOSIT,
            debt_entry::BalanceEntry = DEBT,
            compounded_interest::Bool = false)
    amount >= 0 || throw(ArgumentError("amount must not be negative, got $amount"))
    installments >= 1 || throw(ArgumentError("installments must be at least 1, got $installments"))
    amount = Currency(amount)

    if !(bank_loan || negative_allowed)
        # Only lend out what the creditor actually has available.
        amount = min(amount, available_asset(creditor, money_entry))
    end

    # Book all or nothing.
    if bank_loan
        creditor_money_ok = check_booking(creditor, money_entry, liability, false, amount)
    else
        creditor_money_ok = negative_allowed || check_booking(creditor, money_entry, asset, false, -amount)
    end

    if !(creditor_money_ok &&
            check_booking(creditor, debt_entry, asset, false, amount) &&
            check_booking(debtor, money_entry, asset, false, amount) &&
            check_booking(debtor, debt_entry, liability, false, amount))
        throw(ArgumentError("borrowing $amount would break a balance minimum; nothing was booked"))
    end

    # adjust creditor balance
    if bank_loan
        book_liability!(creditor, money_entry, amount)
    else
        # When negative_allowed is true the creditor's money entry may go below its minimum.
        book_asset!(creditor, money_entry, -amount, skip_check = negative_allowed)
    end

    book_asset!(creditor, debt_entry, amount)

    # adjust debtor balance
    book_asset!(debtor, money_entry, amount)
    book_liability!(debtor, debt_entry, amount)

    return Debt(creditor,
                debtor,
                amount,
                interest_rate,
                installments,
                bank_debt = bank_loan,
                money_entry = money_entry,
                debt_entry = debt_entry,
                creation = timestamp,
                interval = interval,
                compounded_interest = compounded_interest)
end

function bank_loan(creditor::Balance,
            debtor::Balance,
            amount::Real,
            interest_rate::Real,
            installments::Integer,
            interval = 1,
            timestamp::Int64 = 0;
            money_entry::BalanceEntry = DEPOSIT,
            debt_entry::BalanceEntry = DEBT,
            compounded_interest::Bool = false)
    return borrow(creditor, debtor, amount, interest_rate, installments, interval, timestamp, bank_loan = true, money_entry = money_entry, debt_entry = debt_entry, compounded_interest = compounded_interest)
end

"""
    available_asset(balance::Balance, entry::BalanceEntry)

The amount that can be deducted from an asset entry without breaking its minimum. Never negative.
An entry without a practical minimum (see `typemin_asset!`) returns `typemax(Currency)`.
"""
function available_asset(balance::Balance, entry::BalanceEntry)
    value = asset_value(balance, entry)
    minimum = min_asset(balance, entry)

    # Guard against overflow when the minimum is (close to) typemin.
    if minimum < CUR_0 && value > typemax(Currency) + minimum
        return typemax(Currency)
    end

    return max(CUR_0, Currency(value - minimum))
end

debt_settled(debt::Debt) = isempty(debt.installments) && debt.rest_interest == CUR_0

"""
    process_debt!(debt::Debt)

Pay the next installment plus interest. When the debtor can't pay in full, it pays what is available above its
minimum: interest first, the unpaid principal is spread over the remaining installments and unpaid interest is
kept in `rest_interest` or, with compounded interest, added to the debt.

For bank debt only the repaid principal is destroyed. The interest, including repaid capitalised interest, is kept
by the bank as its own money, which raises its equity.

All bookings are checked first. If one would break a balance minimum nothing is changed and an error is thrown.

# Returns
(debt, (paid_installment, paid_interest, shortfall))
"""
function process_debt!(debt::Debt)
    if debt_settled(debt)
        return debt, (CUR_0, CUR_0, CUR_0)
    end

    installments = copy(debt.installments)
    rest_interest = debt.rest_interest
    interest_to_pay = Currency(sum(installments) * debt.interest_rate)
    installment_to_pay = installments[end]
    amount_due = installment_to_pay + interest_to_pay + rest_interest
    capitalised_interest = CUR_0
    shortfall = CUR_0

    if check_booking(debt.debtor, debt.money_entry, asset, false, -amount_due)
        pop!(installments)
        payment = amount_due
        paid_installment = installment_to_pay
        paid_interest = interest_to_pay + rest_interest
        rest_interest = CUR_0
    else
        # Only what is available above the entry's minimum can be paid.
        # Never negative, so paid amounts can't become negative either.
        payment = available_asset(debt.debtor, debt.money_entry)
        spread_shortfall = true

        if length(installments) > 1
            # Downpayment period shuld not be changed, even if full payment of installment is not possible.
            # Exception when last installment cannot be paid in full.
            pop!(installments)
        else
            spread_shortfall = false
        end

        # Calculate which part of the installment cannot be paid.
        shortfall = min(installment_to_pay, amount_due - payment)
        paid_installment = installment_to_pay - shortfall

        # Handle inability to pay interest
        if payment < interest_to_pay + rest_interest
            if debt.compounded_interest
                # Add nonpaid interest to shortfall.
                # When compounded interest is used, rest_interest is always 0.
                capitalised_interest = interest_to_pay - payment
                shortfall += capitalised_interest
            else
                # Adjust rest_interest. Inability to pay rest_interest does not increase rest_interest.
                rest_interest += interest_to_pay - payment
            end

            paid_interest = payment
        else
            paid_interest = interest_to_pay + rest_interest
            rest_interest = CUR_0
        end

        if spread_shortfall
            # Rounded down, with the leftover in the first installment (paid last), as in the Debt constructor.
            installment_increase, rest_increase = split_down(shortfall, length(installments))

            for i in eachindex(installments)
                installments[i] += installment_increase
            end

            installments[1] += rest_increase
        else
            installments[end] = shortfall
        end
    end

    # The unpaid capitalised interest becomes part of the debt on both balance sheets,
    # otherwise later installments would exceed the booked debt.
    debt_change = capitalised_interest - paid_installment

    # Repaid capitalised interest was never created as money, so it is interest, not principal.
    repaid_capitalised = min(paid_installment, debt.capitalised_interest)
    repaid_principal = paid_installment - repaid_capitalised

    if debt.bank_debt
        # The principal is destroyed, the interest is kept by the bank.
        creditor_money_ok = check_booking(debt.creditor, debt.money_entry, liability, false, -repaid_principal) &&
                            check_booking(debt.creditor, debt.money_entry, asset, false, paid_interest + repaid_capitalised)
    else
        creditor_money_ok = check_booking(debt.creditor, debt.money_entry, asset, false, paid_installment + paid_interest)
    end

    if !(creditor_money_ok &&
            check_booking(debt.debtor, debt.money_entry, asset, false, -payment) &&
            check_booking(debt.debtor, debt.debt_entry, liability, false, debt_change) &&
            check_booking(debt.creditor, debt.debt_entry, asset, false, debt_change))
        error("processing debt $(debt.id) would break a balance minimum; nothing was booked")
    end

    book_asset!(debt.debtor, debt.money_entry, -payment)
    book_liability!(debt.debtor, debt.debt_entry, debt_change)

    if debt.bank_debt
        book_liability!(debt.creditor, debt.money_entry, -repaid_principal)
        book_asset!(debt.creditor, debt.money_entry, paid_interest + repaid_capitalised)
    else
        book_asset!(debt.creditor, debt.money_entry, paid_installment + paid_interest)
    end

    book_asset!(debt.creditor, debt.debt_entry, debt_change)

    debt.installments = installments
    debt.rest_interest = rest_interest
    debt.capitalised_interest += capitalised_interest - repaid_capitalised

    return debt, (paid_installment, paid_interest, shortfall)
end
