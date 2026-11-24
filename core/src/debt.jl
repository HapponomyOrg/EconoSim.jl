# Debt contracts.
#
# A debt is a transferable contract between two balance sheets. Bank debt
# creates money when the loan is issued and destroys it when the principal is
# repaid; the interest is a transfer to the creditor.

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
end

function Debt(creditor::Balance, debtor::Balance, installments::Vector{Money},
              interest_rate::Int64; bank_debt::Bool = true,
              money_entry::Entry = DEPOSIT, debt_entry::Entry = DEBT,
              creation::Integer = 0, interval::Integer = 0,
              compounded_interest::Bool = false)
    return Debt(creditor, debtor, copy(installments), interest_rate, bank_debt,
                money_entry, debt_entry, Int64(creation), Int64(interval),
                compounded_interest, MONEY_ZERO)
end

"""
    Debt(creditor, debtor, amount, interest_rate, installments; ...)

Create a debt with equal installments. The rounding remainder is added to the
first installment, which is paid last.
"""
function Debt(creditor::Balance, debtor::Balance, amount::Money,
              interest_rate::Real, installments::Integer;
              bank_debt::Bool = true, money_entry::Entry = DEPOSIT,
              debt_entry::Entry = DEBT, creation::Integer = 0,
              interval::Integer = 0, compounded_interest::Bool = false)
    installments > 0 || throw(ArgumentError("installments must be positive"))
    share, rest = split_amount(amount, Int(installments))
    values = fill(share, Int(installments))
    values[1] = share + rest
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
is created; otherwise it is transferred from the creditor.
"""
function borrow(creditor::Balance, debtor::Balance, amount::Money,
                interest_rate::Real, installments::Integer,
                interval::Integer = 1, timestamp::Integer = 0;
                bank_loan::Bool = true, negative_allowed::Bool = true,
                money_entry::Entry = DEPOSIT, debt_entry::Entry = DEBT,
                compounded_interest::Bool = false)
    if !(bank_loan || negative_allowed)
        amount = asset_value(creditor, money_entry)
    end

    if bank_loan
        book_liability!(creditor, money_entry, amount)
    else
        book_asset!(creditor, money_entry, -amount)
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

Process the next installment. If the debtor cannot pay in full, the shortfall
is spread over the remaining installments (or left as the final installment),
matching MoneySim's behaviour.
"""
function process_debt!(debt::Debt)
    debt_settled(debt) && return debt, (MONEY_ZERO, MONEY_ZERO, MONEY_ZERO)

    interest_to_pay = apply_rate(sum(debt.installments), debt.interest_rate)
    installment_to_pay = debt.installments[end]

    paid_installment = MONEY_ZERO
    paid_interest = MONEY_ZERO
    shortfall = MONEY_ZERO

    if book_asset!(debt.debtor, debt.money_entry,
                   -(installment_to_pay + interest_to_pay + debt.rest_interest))
        pop!(debt.installments)
        paid_installment = installment_to_pay
        paid_interest = interest_to_pay + debt.rest_interest
        debt.rest_interest = MONEY_ZERO
    else
        money_available = asset_value(debt.debtor, debt.money_entry)
        spread_shortfall = true

        if length(debt.installments) > 1
            pop!(debt.installments)
        else
            spread_shortfall = false
        end

        shortfall = min(installment_to_pay,
                        installment_to_pay + interest_to_pay + debt.rest_interest -
                        money_available)
        paid_installment = installment_to_pay - shortfall

        if money_available < interest_to_pay + debt.rest_interest
            if debt.compounded_interest
                shortfall += interest_to_pay - money_available
            else
                debt.rest_interest += interest_to_pay - money_available
            end
            paid_interest = money_available
        else
            paid_interest = interest_to_pay + debt.rest_interest
            debt.rest_interest = MONEY_ZERO
        end

        if spread_shortfall
            share, rest = split_amount(shortfall, length(debt.installments))
            for i in eachindex(debt.installments)
                debt.installments[i] += share
            end
            debt.installments[end] += rest
        else
            debt.installments[end] = shortfall
        end

        book_asset!(debt.debtor, debt.money_entry, -money_available)
    end

    book_liability!(debt.debtor, debt.debt_entry, -paid_installment)

    if debt.bank_debt
        book_liability!(debt.creditor, debt.money_entry,
                        -(paid_installment + paid_interest))
    else
        book_asset!(debt.creditor, debt.money_entry,
                    paid_installment + paid_interest)
    end

    book_asset!(debt.creditor, debt.debt_entry, -paid_installment)

    return debt, (paid_installment, paid_interest, shortfall)
end

export Debt, debt_settled, borrow, bank_loan, process_debt!
