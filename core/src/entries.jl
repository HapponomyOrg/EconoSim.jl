# Ledger entry identifiers.
#
# Replaces the UUID + Symbol keyed `BalanceEntry` with a small integer enum.
# The set is fixed at compile time, so a balance sheet can store one value per
# entry in a plain Vector.

const Entry = Int32
const Side = Int32

const EQUITY = Int32(1)
const DEPOSIT = Int32(2)
const DEBT = Int32(3)
const SUMSY_DEPOSIT = Int32(4)
const SUMSY_DEBT = Int32(5)

const ASSET = Int32(1)
const LIABILITY = Int32(2)

const N_ENTRIES = 5

# Compatibility aliases used by the existing MoneySim vocabulary.
const SUMSY_DEP = SUMSY_DEPOSIT

@inline entry_index(entry::Entry) = Int(entry)

export Entry, Side, EQUITY, DEPOSIT, DEBT, SUMSY_DEPOSIT, SUMSY_DEBT, N_ENTRIES, SUMSY_DEP
export ASSET, LIABILITY, entry_index
