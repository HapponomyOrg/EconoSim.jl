# Ledger entry identifiers.
#
# Replaces the UUID + Symbol keyed `BalanceEntry` with a small integer enum.
# The default schema has five slots; the fixed capacity leaves room for
# MacroSim instruments (bonds, shares, typed loans, ...) without dynamic
# dictionaries in the wasm path.

const Entry = Int32
const Side = Int32

const EQUITY = Int32(1)
const DEPOSIT = Int32(2)
const DEBT = Int32(3)
const SUMSY_DEPOSIT = Int32(4)
const SUMSY_DEBT = Int32(5)

# Reserved slots for extension models. They are ordinary ledger entries as far
# as `Balance` is concerned; the core does not interpret them.
const BOND = Int32(6)
const SHARE = Int32(7)
const LOAN_RECEIVABLE = Int32(8)
const LOAN_PAYABLE = Int32(9)
const CUSTOM_ENTRY_FIRST = Int32(10)

const ASSET = Int32(1)
const LIABILITY = Int32(2)

const N_ENTRIES = Int(SUMSY_DEBT)
const MAX_ENTRIES = 32

"""
    LedgerSchema(count = N_ENTRIES)

The number of active ledger slots. Existing five-entry behaviour is the
default; extended models may activate up to `MAX_ENTRIES` slots. Slots are
fixed at allocation time so `Balance` stays an array-backed wasm-friendly
structure.
"""
struct LedgerSchema
    count::Int32
    function LedgerSchema(count::Integer = N_ENTRIES)
        N_ENTRIES <= count <= MAX_ENTRIES ||
            throw(ArgumentError("ledger schema must have $N_ENTRIES..$MAX_ENTRIES entries"))
        return new(Int32(count))
    end
end

const DEFAULT_LEDGER_SCHEMA = LedgerSchema()

# Compatibility aliases used by the existing MoneySim vocabulary.
const SUMSY_DEP = SUMSY_DEPOSIT

@inline entry_index(entry::Entry) = Int(entry)
@inline entry_count(balance) = Int(balance.count)

export Entry, Side, EQUITY, DEPOSIT, DEBT, SUMSY_DEPOSIT, SUMSY_DEBT, N_ENTRIES, SUMSY_DEP
export BOND, SHARE, LOAN_RECEIVABLE, LOAN_PAYABLE, CUSTOM_ENTRY_FIRST
export MAX_ENTRIES, LedgerSchema, DEFAULT_LEDGER_SCHEMA, entry_count
export ASSET, LIABILITY, entry_index
