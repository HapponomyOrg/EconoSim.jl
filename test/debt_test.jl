using Test
using EconoSim

# Total money on a set of non-bank balances. Must be conserved by non-bank loans.
money(balances...) = sum(asset_value(b, DEPOSIT) for b in balances)

function bank_balance()
    bank = Balance()
    typemin_liability!(bank, DEPOSIT) # Deposits held at the bank are unbounded.
    return bank
end

@testset "Debt - bank loan, no interest" begin
    bank = bank_balance()
    debtor = Balance()
    debt = bank_loan(bank, debtor, 100, 0, 4)

    @test asset_value(debtor, DEPOSIT) == 100
    @test liability_value(debtor, DEBT) == 100
    @test asset_value(bank, DEBT) == 100
    @test liability_value(bank, DEPOSIT) == 100
    @test debt.installments == fill(Currency(25), 4)

    for i in 1:4
        _, (paid_installment, paid_interest, shortfall) = process_debt!(debt)
        @test paid_installment == 25
        @test paid_interest == 0
        @test shortfall == 0
    end

    @test debt_settled(debt)
    @test asset_value(debtor, DEPOSIT) == 0
    @test liability_value(debtor, DEBT) == 0
    @test asset_value(bank, DEBT) == 0
    @test liability_value(bank, DEPOSIT) == 0
    @test validate(bank) && validate(debtor)

    # Processing a settled debt does nothing.
    _, paid = process_debt!(debt)
    @test paid == (0, 0, 0)
end

@testset "Debt - bank loan with interest" begin
    bank = bank_balance()
    debtor = Balance()
    book_asset!(debtor, DEPOSIT, 100)
    debt = bank_loan(bank, debtor, 100, 0.1, 2)

    _, (paid_installment, paid_interest, shortfall) = process_debt!(debt)
    @test (paid_installment, paid_interest, shortfall) == (50, 10, 0)
    _, (paid_installment, paid_interest, shortfall) = process_debt!(debt)
    @test (paid_installment, paid_interest, shortfall) == (50, 5, 0)

    @test debt_settled(debt)
    @test asset_value(debtor, DEPOSIT) == 200 - 115
    @test liability_value(debtor, DEBT) == 0
    @test asset_value(bank, DEBT) == 0
    @test validate(bank) && validate(debtor)
end

@testset "Debt - non-bank loan limited to available money" begin
    creditor = Balance()
    debtor = Balance()
    book_asset!(creditor, DEPOSIT, 50)

    debt = borrow(creditor, debtor, 100, 0, 2, bank_loan = false, negative_allowed = false)
    @test sum(debt.installments) == 50
    @test asset_value(creditor, DEPOSIT) == 0
    @test asset_value(debtor, DEPOSIT) == 50
    @test asset_value(creditor, DEBT) == 50
    @test liability_value(debtor, DEBT) == 50

    # Requests below the available amount are not inflated to the whole balance.
    creditor = Balance()
    debtor = Balance()
    book_asset!(creditor, DEPOSIT, 500)
    debt = borrow(creditor, debtor, 100, 0, 2, bank_loan = false, negative_allowed = false)
    @test sum(debt.installments) == 100
    @test asset_value(creditor, DEPOSIT) == 400
    @test asset_value(debtor, DEPOSIT) == 100

    # The creditor's minimum is respected.
    creditor = Balance()
    debtor = Balance()
    book_asset!(creditor, DEPOSIT, 50)
    min_asset!(creditor, DEPOSIT, 20)
    debt = borrow(creditor, debtor, 100, 0, 2, bank_loan = false, negative_allowed = false)
    @test sum(debt.installments) == 30
    @test asset_value(creditor, DEPOSIT) == 20
    @test asset_value(debtor, DEPOSIT) == 30
end

@testset "Debt - non-bank loan, negative allowed" begin
    creditor = Balance()
    debtor = Balance()
    book_asset!(creditor, DEPOSIT, 50)

    debt = borrow(creditor, debtor, 100, 0, 2, bank_loan = false, negative_allowed = true)
    @test sum(debt.installments) == 100
    @test asset_value(creditor, DEPOSIT) == -50
    @test asset_value(debtor, DEPOSIT) == 100
    @test money(creditor, debtor) == 50 # No money created.
    @test validate(creditor) && validate(debtor)
end

@testset "Debt - custom debt entry" begin
    loan_entry = BalanceEntry("Custom loan")

    creditor = Balance()
    debtor = Balance()
    book_asset!(creditor, DEPOSIT, 100)
    debt = borrow(creditor, debtor, 100, 0, 2, bank_loan = false, negative_allowed = false, debt_entry = loan_entry)

    @test asset_value(creditor, loan_entry) == 100
    process_debt!(debt)
    process_debt!(debt)

    @test debt_settled(debt)
    @test asset_value(creditor, loan_entry) == 0
    @test asset_value(creditor, DEBT) == 0
    @test liability_value(debtor, loan_entry) == 0
    @test asset_value(creditor, DEPOSIT) == 100
    @test validate(creditor) && validate(debtor)

    # Same for bank loans.
    bank = bank_balance()
    debtor = Balance()
    debt = bank_loan(bank, debtor, 100, 0, 1, debt_entry = loan_entry)
    process_debt!(debt)
    @test debt_settled(debt)
    @test asset_value(bank, loan_entry) == 0
    @test asset_value(bank, DEBT) == 0
end

@testset "Debt - partial payment spreads shortfall" begin
    creditor = Balance()
    debtor = Balance()
    book_asset!(creditor, DEPOSIT, 100)
    debt = borrow(creditor, debtor, 100, 0, 4, bank_loan = false, negative_allowed = false)

    book_asset!(debtor, DEPOSIT, -90) # Debtor spends most of the loan.
    total_money = money(creditor, debtor)

    _, (paid_installment, paid_interest, shortfall) = process_debt!(debt)
    @test (paid_installment, paid_interest, shortfall) == (10, 0, 15)
    @test debt.installments == fill(Currency(30), 3)
    @test asset_value(debtor, DEPOSIT) == 0
    @test liability_value(debtor, DEBT) == 90
    @test asset_value(creditor, DEBT) == 90
    @test money(creditor, debtor) == total_money
    @test validate(creditor) && validate(debtor)
end

@testset "Debt - partial payment respects minimum" begin
    creditor = Balance()
    debtor = Balance()
    book_asset!(creditor, DEPOSIT, 100)
    debt = borrow(creditor, debtor, 100, 0, 4, bank_loan = false, negative_allowed = false)

    book_asset!(debtor, DEPOSIT, -90)
    min_asset!(debtor, DEPOSIT, 5)
    total_money = money(creditor, debtor)

    _, (paid_installment, paid_interest, shortfall) = process_debt!(debt)
    @test (paid_installment, paid_interest, shortfall) == (5, 0, 20)
    @test asset_value(debtor, DEPOSIT) == 5
    @test money(creditor, debtor) == total_money # No money created.
    @test liability_value(debtor, DEBT) == 95
    @test asset_value(creditor, DEBT) == 95
end

@testset "Debt - partial payment from negative balance" begin
    creditor = Balance()
    debtor = Balance()
    book_asset!(creditor, DEPOSIT, 100)
    debt = borrow(creditor, debtor, 100, 0, 4, bank_loan = false, negative_allowed = false)

    min_asset!(debtor, DEPOSIT, -20)
    book_asset!(debtor, DEPOSIT, -110) # Overdrawn: -10, 10 left before the minimum.
    total_money = money(creditor, debtor)

    _, (paid_installment, paid_interest, shortfall) = process_debt!(debt)
    @test (paid_installment, paid_interest, shortfall) == (10, 0, 15)
    @test asset_value(debtor, DEPOSIT) == -20
    @test money(creditor, debtor) == total_money

    # Nothing available: nothing paid, never a negative payment.
    _, (paid_installment, paid_interest, shortfall) = process_debt!(debt)
    @test paid_installment == 0
    @test paid_interest == 0
    @test asset_value(debtor, DEPOSIT) == -20
    @test money(creditor, debtor) == total_money
end

@testset "Debt - unpaid interest, not compounded" begin
    bank = bank_balance()
    debtor = Balance()
    debt = bank_loan(bank, debtor, 100, 0.1, 2)
    book_asset!(debtor, DEPOSIT, -95)

    _, (paid_installment, paid_interest, shortfall) = process_debt!(debt)
    @test (paid_installment, paid_interest, shortfall) == (0, 5, 50)
    @test debt.rest_interest == 5
    @test debt.installments == [Currency(100)]
    @test liability_value(debtor, DEBT) == 100

    book_asset!(debtor, DEPOSIT, 200)
    _, (paid_installment, paid_interest, shortfall) = process_debt!(debt)
    @test (paid_installment, paid_interest, shortfall) == (100, 15, 0)
    @test debt_settled(debt)
    @test liability_value(debtor, DEBT) == 0
    @test asset_value(bank, DEBT) == 0
    @test validate(bank) && validate(debtor)
end

@testset "Debt - unpaid interest, compounded" begin
    bank = bank_balance()
    debtor = Balance()
    debt = bank_loan(bank, debtor, 100, 0.1, 2, compounded_interest = true)
    book_asset!(debtor, DEPOSIT, -95)

    _, (paid_installment, paid_interest, shortfall) = process_debt!(debt)
    @test (paid_installment, paid_interest, shortfall) == (0, 5, 55)
    @test debt.rest_interest == 0
    @test debt.installments == [Currency(105)]
    # Capitalised interest is booked as debt on both sides.
    @test liability_value(debtor, DEBT) == 105
    @test asset_value(bank, DEBT) == 105

    book_asset!(debtor, DEPOSIT, 200)
    _, (paid_installment, paid_interest, shortfall) = process_debt!(debt)
    @test paid_installment == 105
    @test debt_settled(debt)
    @test liability_value(debtor, DEBT) == 0
    @test asset_value(bank, DEBT) == 0
    @test validate(bank) && validate(debtor)
end

@testset "Debt - last installment partially paid" begin
    bank = bank_balance()
    debtor = Balance()
    debt = bank_loan(bank, debtor, 100, 0, 1)
    book_asset!(debtor, DEPOSIT, -70)

    _, (paid_installment, paid_interest, shortfall) = process_debt!(debt)
    @test (paid_installment, paid_interest, shortfall) == (30, 0, 70)
    @test debt.installments == [Currency(70)]
    @test !debt_settled(debt)

    book_asset!(debtor, DEPOSIT, 70)
    process_debt!(debt)
    @test debt_settled(debt)
    @test liability_value(debtor, DEBT) == 0
end

@testset "Debt - available asset" begin
    b = Balance()
    book_asset!(b, DEPOSIT, 30)
    @test EconoSim.available_asset(b, DEPOSIT) == 30
    min_asset!(b, DEPOSIT, 50)
    @test EconoSim.available_asset(b, DEPOSIT) == 0
    typemin_asset!(b, DEPOSIT)
    @test EconoSim.available_asset(b, DEPOSIT) == typemax(Currency)
end

@testset "Debt - bank keeps interest, destroys principal" begin
    bank = Balance() # Plain balance: the bank's deposits can't go below 0.
    debtor = Balance()
    book_asset!(debtor, DEPOSIT, 100)
    debt = bank_loan(bank, debtor, 100, 0.1, 1)

    _, paid = process_debt!(debt)
    @test paid == (100, 10, 0)
    @test debt_settled(debt)
    @test asset_value(debtor, DEPOSIT) == 90
    @test liability_value(debtor, DEBT) == 0
    @test liability_value(bank, DEPOSIT) == 0 # The principal is destroyed.
    @test asset_value(bank, DEPOSIT) == 10 # The interest is kept by the bank.
    @test asset_value(bank, DEBT) == 0
    @test equity(bank) == 10
    @test validate(bank) && validate(debtor)
end

@testset "Debt - capitalised interest is kept by the bank" begin
    bank = Balance()
    debtor = Balance()
    debt = bank_loan(bank, debtor, 100, 0.1, 2, compounded_interest = true)
    book_asset!(debtor, DEPOSIT, -100)

    # Nothing can be paid: the interest is added to the debt.
    _, paid = process_debt!(debt)
    @test paid == (0, 0, 60)
    @test debt.installments == [Currency(110)]
    @test debt.capitalised_interest == 10
    @test liability_value(debtor, DEBT) == 110
    @test asset_value(bank, DEBT) == 110

    book_asset!(debtor, DEPOSIT, 200)
    _, paid = process_debt!(debt)
    @test paid == (110, 11, 0)
    @test debt_settled(debt)
    @test debt.capitalised_interest == 0
    @test liability_value(bank, DEPOSIT) == 0 # Exactly the principal of 100 is destroyed.
    @test asset_value(bank, DEPOSIT) == 21 # 10 capitalised interest + 11 interest.
    @test asset_value(bank, DEBT) == 0
    @test equity(bank) == 21
    @test asset_value(debtor, DEPOSIT) == 79
    @test validate(bank) && validate(debtor)
end

@testset "Debt - process_debt! is all-or-nothing" begin
    bank = Balance()
    debtor = Balance()
    debt = bank_loan(bank, debtor, 100, 0, 2)
    book_liability!(debtor, DEBT, -80) # The debt entry is reduced outside the Debt.

    @test_throws ErrorException process_debt!(debt)
    @test debt.installments == fill(Currency(50), 2)
    @test asset_value(debtor, DEPOSIT) == 100
    @test liability_value(debtor, DEBT) == 20
    @test liability_value(bank, DEPOSIT) == 100
    @test asset_value(bank, DEBT) == 100
end

@testset "Debt - borrow validates before booking" begin
    creditor = Balance()
    debtor = Balance()

    @test_throws ArgumentError borrow(creditor, debtor, -50, 0, 1, bank_loan = false, negative_allowed = false)
    @test_throws ArgumentError bank_loan(creditor, debtor, 100, 0, 0)

    # The debtor's debt entry can't take the loan.
    min_liability!(debtor, DEBT, 10)
    @test_throws ArgumentError bank_loan(creditor, debtor, 5, 0, 1)

    for balance in (creditor, debtor), entry in (DEPOSIT, DEBT)
        @test asset_value(balance, entry) == 0
        @test liability_value(balance, entry) == 0
    end
end

@testset "Debt - installments are rounded down, never negative" begin
    unit = eps(Currency)
    bank = Balance()
    debtor = Balance()

    for amount in (17 * unit, Currency(100), Currency(100) + 6 * unit, Currency(1) - unit, Currency(0)), n in (1, 3, 12, 20)
        installments = Debt(bank, debtor, amount, 0, n).installments
        @test sum(installments) == amount
        @test all(i -> i >= 0, installments)
        @test all(i -> i == installments[end], installments[2:end])
        @test 0 <= installments[1] - installments[end] < n * unit
    end

    # 100 / 12 already rounded down to the nearest unit, so its installments are unchanged.
    @test Debt(bank, debtor, 100, 0, 12).installments == [Currency(100) - 11 * Currency(100 / 12); fill(Currency(100 / 12), 11)]
end

@testset "Debt - a tiny bank loan is paid off in full" begin
    unit = eps(Currency)
    bank = Balance()
    debtor = Balance()
    debt = bank_loan(bank, debtor, 17 * unit, 0, 20) # Rounding to nearest gave 19 x 1 unit and -2 units.

    for _ in 1:20
        process_debt!(debt)
    end

    @test debt_settled(debt)
    @test liability_value(debtor, DEBT) == 0
    @test asset_value(debtor, DEPOSIT) == 0
    @test liability_value(bank, DEPOSIT) == 0
    @test asset_value(bank, DEBT) == 0
    @test validate(debtor) && validate(bank)
end

@testset "Debt - a spread shortfall is rounded down, leftover paid last" begin
    unit = eps(Currency)
    bank = Balance()
    debtor = Balance()
    debt = bank_loan(bank, debtor, 100, 0, 4)
    book_asset!(debtor, DEPOSIT, -(75 + 2 * unit)) # The debtor can pay 25 - 2 units.

    _, (paid_installment, paid_interest, shortfall) = process_debt!(debt)
    @test (paid_installment, paid_interest, shortfall) == (25 - 2 * unit, 0, 2 * unit)
    # 2 units over 3 installments: nothing each, the 2 units in the first installment.
    @test debt.installments == [25 + 2 * unit, Currency(25), Currency(25)]
    @test liability_value(debtor, DEBT) == sum(debt.installments)
end
