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
            CUR_0)
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

Create a debt contract between two balances with a number of equal installments.

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
    installment = Currency(amount / installments)
    rest = Currency(amount) - installment * installments
    installment_vector = fill(installment, (installments))

    # Make sure the entire debt is paid off.
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
    if !(bank_loan || negative_allowed)
        amount = min(asset_value(creditor, money_entry))
    end

    amount = Currency(amount)

    # adjust creditor balance
    if bank_loan
        book_liability!(creditor, money_entry, amount)
    else
        book_asset!(creditor, money_entry, -amount)
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

debt_settled(debt::Debt) = isempty(debt.installments)

function process_debt!(debt::Debt)
    if !debt_settled(debt)
        interest_to_pay = Currency(sum(debt.installments) * debt.interest_rate)
        installment_to_pay = debt.installments[end]

        paid_installment = CUR_0
        paid_interest = CUR_0

        # adjust debtor balance
        if book_asset!(debt.debtor, debt.money_entry, -(installment_to_pay + interest_to_pay + debt.rest_interest))
            pop!(debt.installments)
            paid_installment = installment_to_pay
            paid_interest = interest_to_pay + debt.rest_interest
            debt.rest_interest = CUR_0
        else
            money = asset_value(debt.debtor, debt.money_entry)

            if length(debt.installments) > 1
                # Downpayment period shuld not be changed, even if full payment of installment is not possible.
                # Exception when last installment cannot be paid in full.
                pop!(debt.installments)

                # Calculate which part of the installment cannot be paid.
                unpaid_debt = min(installment_to_pay, installment_to_pay + interest_to_pay + debt.rest_interest - money)
                paid_installment = installment_to_pay - unpaid_debt
            end

            # Handle inability to pay interest
            if money < interest_to_pay + debt.rest_interest
                if debt.compounded_interest
                    # Add nonpaid interest to unpaid_debt.
                    # When compounded interest is used, rest_interest is always 0.
                    unpaid_debt += interest_to_pay - money
                else
                    # Adjust rest_interest. Inability to pay rest_interest does not increase rest_interest.
                    debt.rest_interest += interest_to_pay - money
                end

                paid_interest = money
            else
                paid_interest = interest_to_pay + debt.rest_interest
                debt.rest_interest = CUR_0
            end

            installment_increase = Currency(unpaid_debt / length(debt.installments))
            rest_increase = unpaid_debt - installment_increase * length(debt.installments)

            for i in eachindex(debt.installments)
                debt.installments[i] += installment_increase
            end

            debt.installments[end] += rest_increase

            book_asset!(debt.debtor, debt.money_entry, -money)
        end

        book_liability!(debt.debtor, debt.debt_entry, -paid_installment)

        #adjust creditor balance
        if debt.bank_debt
            book_liability!(debt.creditor, debt.money_entry, -(paid_installment + paid_interest))
        else
            book_asset!(debt.creditor, debt.money_entry, paid_installment + paid_interest)
        end

        book_asset!(debt.creditor, DEBT, -paid_installment)
    end

    return debt
end
