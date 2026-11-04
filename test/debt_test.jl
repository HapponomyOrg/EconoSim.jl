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
