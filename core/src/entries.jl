# Ledger entry identifiers.
#
# Replaces the UUID + Symbol keyed `BalanceEntry` with a small integer enum.
# The set is fixed at compile time, so a balance sheet can store one value per
# entry in a plain Vector.

@enum Entry::Int32 begin
    EQUITY = 1
    DEPOSIT = 2
    DEBT = 3
    SUMSY_DEPOSIT = 4
    SUMSY_DEBT = 5
end

@enum Side::Int32 begin
    ASSET = 1
    LIABILITY = 2
end

const N_ENTRIES = 5

# Compatibility aliases used by the existing MoneySim vocabulary.
const SUMSY_DEP = SUMSY_DEPOSIT

@inline entry_index(entry::Entry) = Int(entry)

export Entry, Side, EQUITY, DEPOSIT, DEBT, SUMSY_DEPOSIT, SUMSY_DEBT, N_ENTRIES, SUMSY_DEP
export ASSET, LIABILITY, entry_index
