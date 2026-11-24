# Debt contracts.
#
# A debt is a transferable contract between two balance sheets. Bank debt
# creates money when the loan is issued and destroys the principal when it is
# repaid; interest is a transfer to the creditor. Installments round down and
# the leftover goes into the first installment, which is paid last.

mutable struct Debt
    creditor::Balance
    debtor::Balance
    installments::Vector{Money}
    interest_rate::Int64
    bank_debt::Bool
    money_entry::Entry
    debt_entry::Entry
    creation::Int64
    interval::Int64
    compounded_interest::Bool
    rest_interest::Money
    capitalised_interest::Money
end

function Debt(creditor::Balance, debtor::Balance, installments::Vector{Money},
              interest_rate::Int64; bank_debt::Bool = true,
              money_entry::Entry = DEPOSIT, debt_entry::Entry = DEBT,
              creation::Integer = 0, interval::Integer = 0,
              compounded_interest::Bool = false)
    return Debt(creditor, debtor, copy(installments), interest_rate, bank_debt,
                money_entry, debt_entry, Int64(creation), Int64(interval),
                compounded_interest, MONEY_ZERO, MONEY_ZERO)
end

"""
    split_down(total::Money, n::Integer) -> (part, leftover)

Split `total` into `n` equal parts rounded down, with
`part * n + leftover == total` and `0 <= leftover < n`. Rounding to nearest
instead can produce a negative leftover, which would make the first installment
negative. Mirrors main EconoSim's `split_down`.
"""
function split_down(total::Money, n::Integer)
    part = Money(fld(total.value, Int64(n)))
    return part, total - part * Int64(n)
end

"""
    Debt(creditor, debtor, amount, interest_rate, installments; ...)

Create a debt with equal installments rounded down. The leftover goes into the
first installment, which is paid last, so no installment is negative.
"""
function Debt(creditor::Balance, debtor::Balance, amount::Money,
              interest_rate::Real, installments::Integer;
              bank_debt::Bool = true, money_entry::Entry = DEPOSIT,
              debt_entry::Entry = DEBT, creation::Integer = 0,
              interval::Integer = 0, compounded_interest::Bool = false)
    installments >= 1 || throw(ArgumentError("installments must be at least 1, got $installments"))
    installment, rest = split_down(amount, installments)
    values = fill(installment, Int(installments))
    values[1] = installment + rest
    return Debt(creditor, debtor, values, ppm(interest_rate);
                bank_debt = bank_debt, money_entry = money_entry,
                debt_entry = debt_entry, creation = creation,
                interval = interval, compounded_interest = compounded_interest)
end

debt_settled(debt::Debt) = isempty(debt.installments) && debt.rest_interest == MONEY_ZERO

"""
    borrow(creditor, debtor, amount, interest_rate, installments, interval = 1,
           timestamp = 0; bank_loan = true, ...)

Issue a loan and update both balance sheets. With `bank_loan = true` the money
is created; otherwise it is transferred from the creditor. All bookings are
checked first: if one would break a balance minimum, nothing is booked.
"""
function borrow(creditor::Balance, debtor::Balance, amount::Money,
                interest_rate::Real, installments::Integer,
                interval::Integer = 1, timestamp::Integer = 0;
                bank_loan::Bool = true, negative_allowed::Bool = true,
                money_entry::Entry = DEPOSIT, debt_entry::Entry = DEBT,
                compounded_interest::Bool = false)
    amount >= MONEY_ZERO ||
        throw(ArgumentError("amount must not be negative, got $(currency(amount))"))
    installments >= 1 ||
        throw(ArgumentError("installments must be at least 1, got $installments"))

    if !(bank_loan || negative_allowed)
        # Only lend out what the creditor actually has available.
        amount = min(amount, available_asset(creditor, money_entry))
    end

    if bank_loan
        creditor_money_ok = check_booking(creditor, money_entry, LIABILITY,
                                          false, amount)
    else
        creditor_money_ok = negative_allowed ||
            check_booking(creditor, money_entry, ASSET, false, -amount)
    end

    if !(creditor_money_ok &&
         check_booking(creditor, debt_entry, ASSET, false, amount) &&
         check_booking(debtor, money_entry, ASSET, false, amount) &&
         check_booking(debtor, debt_entry, LIABILITY, false, amount))
        throw(ArgumentError("borrowing $(currency(amount)) would break a balance minimum; nothing was booked"))
    end

    if bank_loan
        book_liability!(creditor, money_entry, amount)
    else
        # When negative_allowed is true the creditor's money entry may go below
        # its minimum.
        book_asset!(creditor, money_entry, -amount, skip_check = negative_allowed)
    end
    book_asset!(creditor, debt_entry, amount)

    book_asset!(debtor, money_entry, amount)
    book_liability!(debtor, debt_entry, amount)

    return Debt(creditor, debtor, amount, interest_rate, installments;
                bank_debt = bank_loan, money_entry = money_entry,
                debt_entry = debt_entry, creation = timestamp,
                interval = interval, compounded_interest = compounded_interest)
end

bank_loan(creditor::Balance, debtor::Balance, amount::Money,
          interest_rate::Real, installments::Integer,
          interval::Integer = 1, timestamp::Integer = 0; kwargs...) =
    borrow(creditor, debtor, amount, interest_rate, installments, interval,
           timestamp; bank_loan = true, kwargs...)

"""
    process_debt!(debt) -> (debt, (paid_installment, paid_interest, shortfall))

Pay the next installment plus interest. When the debtor cannot pay in full it
pays what is available above its minimum: interest first, the unpaid principal
is spread over the remaining installments, and unpaid interest is kept in
`rest_interest` or, with compounded interest, added to the debt.

For bank debt only the repaid principal is destroyed. Interest, including
repaid capitalised interest, stays with the bank as its own money.

All bookings are checked first; if one would break a balance minimum nothing is
changed and an error is thrown.
"""
function process_debt!(debt::Debt)
    debt_settled(debt) && return debt, (MONEY_ZERO, MONEY_ZERO, MONEY_ZERO)

    installments = copy(debt.installments)
    rest_interest = debt.rest_interest
    interest_to_pay = apply_rate(sum(installments), debt.interest_rate)
    installment_to_pay = installments[end]
    amount_due = installment_to_pay + interest_to_pay + rest_interest
    capitalised_interest = MONEY_ZERO
    shortfall = MONEY_ZERO

    if check_booking(debt.debtor, debt.money_entry, ASSET, false, -amount_due)
        pop!(installments)
        payment = amount_due
        paid_installment = installment_to_pay
        paid_interest = interest_to_pay + rest_interest
        rest_interest = MONEY_ZERO
    else
        # Only what is available above the entry's minimum can be paid.
        payment = available_asset(debt.debtor, debt.money_entry)
        spread_shortfall = true

        if length(installments) > 1
            pop!(installments)
        else
            spread_shortfall = false
        end

        shortfall = min(installment_to_pay, amount_due - payment)
        paid_installment = installment_to_pay - shortfall

        if payment < interest_to_pay + rest_interest
            if debt.compounded_interest
                # With compounded interest, rest_interest stays zero.
                capitalised_interest = interest_to_pay - payment
                shortfall += capitalised_interest
            else
                rest_interest += interest_to_pay - payment
            end
            paid_interest = payment
        else
            paid_interest = interest_to_pay + rest_interest
            rest_interest = MONEY_ZERO
        end

        if spread_shortfall
            increase, rest_increase = split_down(shortfall, length(installments))
            for i in eachindex(installments)
                installments[i] += increase
            end
            installments[1] += rest_increase
        else
            installments[end] = shortfall
        end
    end

    # Unpaid capitalised interest becomes part of the debt on both sheets.
    debt_change = capitalised_interest - paid_installment

    # Repaid capitalised interest was never created as money, so it counts as
    # interest, not principal.
    repaid_capitalised = min(paid_installment, debt.capitalised_interest)
    repaid_principal = paid_installment - repaid_capitalised

    if debt.bank_debt
        creditor_money_ok =
            check_booking(debt.creditor, debt.money_entry, LIABILITY, false,
                          -repaid_principal) &&
            check_booking(debt.creditor, debt.money_entry, ASSET, false,
                          paid_interest + repaid_capitalised)
    else
        creditor_money_ok =
            check_booking(debt.creditor, debt.money_entry, ASSET, false,
                          paid_installment + paid_interest)
    end

    if !(creditor_money_ok &&
         check_booking(debt.debtor, debt.money_entry, ASSET, false, -payment) &&
         check_booking(debt.debtor, debt.debt_entry, LIABILITY, false, debt_change) &&
         check_booking(debt.creditor, debt.debt_entry, ASSET, false, debt_change))
        error("processing debt would break a balance minimum; nothing was booked")
    end

    book_asset!(debt.debtor, debt.money_entry, -payment)
    book_liability!(debt.debtor, debt.debt_entry, debt_change)

    if debt.bank_debt
        book_liability!(debt.creditor, debt.money_entry, -repaid_principal)
        book_asset!(debt.creditor, debt.money_entry,
                    paid_interest + repaid_capitalised)
    else
        book_asset!(debt.creditor, debt.money_entry,
                    paid_installment + paid_interest)
    end

    book_asset!(debt.creditor, debt.debt_entry, debt_change)

    debt.installments = installments
    debt.rest_interest = rest_interest
    debt.capitalised_interest += capitalised_interest - repaid_capitalised

    return debt, (paid_installment, paid_interest, shortfall)
end

export Debt, debt_settled, borrow, bank_loan, process_debt!, split_down
