# Integer fixed-point money.
#
# Money is stored as an Int64 scaled by 10^4 (currency × 10,000), matching the
# four-decimal precision MoneySim uses, but without FixedPointDecimals.
# Rates are permyriad (rate × 10,000).

const SCALE = Int64(10_000)
const PERMYRIAD = SCALE

"""
    Money(value::Int64)

An exact amount of money, scaled by `10^4`.

`Money(value)` is the raw scaled value; use [`money`](@ref) to construct from
currency units (`money(12.34) == Money(123_400)`).
"""
struct Money
    value::Int64
end

"""    money(x::Real) -> Money

Construct `Money` from currency units, rounding to four decimals.
"""
@inline money(x::Real) = Money(round(Int64, x * SCALE))
@inline money(x::Integer) = Money(Int64(x) * SCALE)

"""    scaled(x::Integer) -> Money

Construct `Money` from an already-scaled integer value.
"""
@inline scaled(x::Integer) = Money(Int64(x))

"""    currency(m::Money) -> Float64

Convert `Money` to currency units for reporting.
"""
@inline currency(m::Money) = Float64(m.value) / SCALE

const MONEY_ZERO = Money(0)

Base.zero(::Type{Money}) = MONEY_ZERO
Base.zero(::Money) = MONEY_ZERO
Base.typemin(::Type{Money}) = Money(typemin(Int64))
Base.typemax(::Type{Money}) = Money(typemax(Int64))
Base.iszero(m::Money) = m.value == 0

@inline Base.:+(a::Money, b::Money) = Money(a.value + b.value)
@inline Base.:-(a::Money, b::Money) = Money(a.value - b.value)
@inline Base.:-(a::Money) = Money(-a.value)
@inline Base.:*(a::Money, b::Integer) = Money(a.value * b)
@inline Base.:*(b::Integer, a::Money) = Money(a.value * b)
@inline Base.:(==)(a::Money, b::Money) = a.value == b.value
@inline Base.isless(a::Money, b::Money) = isless(a.value, b.value)
@inline Base.hash(m::Money, h::UInt) = hash(m.value, h)
@inline Base.abs(m::Money) = Money(abs(m.value))
@inline Base.sign(m::Money) = sign(m.value)

Base.Float64(m::Money) = currency(m)
Base.broadcastable(m::Money) = Ref(m)
Base.show(io::IO, m::Money) = print(io, "Money(", currency(m), ")")

@inline Base.div(a::Money, b::Integer) = Money(div(a.value, b))
@inline Base.rem(a::Money, b::Integer) = Money(rem(a.value, b))
@inline Base.divrem(a::Money, b::Integer) = (Money(div(a.value, b)), Money(rem(a.value, b)))

"""    permyriad(x::Real) -> Int64

Convert a rate to permyriad (rate × 10,000), rounded to an integer.
"""
@inline permyriad(x::Real) = round(Int64, x * PERMYRIAD)

"""    rate(x::Int64) -> Float64

Convert permyriad back to a rate for reporting.
"""
@inline rate(x::Int64) = Float64(x) / PERMYRIAD

"""
    apply_rate(value::Money, permyriad_rate::Int64) -> Money

Apply a permyriad rate to an amount. The intermediate product is split so that
`q * rate` cannot overflow for realistic simulation amounts.
"""
@inline function apply_rate(value::Money, permyriad_rate::Int64)
    q, r = divrem(value.value, PERMYRIAD)
    return Money(q * permyriad_rate + div(r * permyriad_rate, PERMYRIAD))
end

@inline apply_rate(value::Money, permyriad_rate::Real) =
    apply_rate(value, permyriad(permyriad_rate))

"""
    split_amount(total::Money, parts::Int) -> (share::Money, remainder::Money)

Split a total into `parts` equal shares plus a remainder. The caller decides
who receives the remainder (deterministically, or via an explicit RNG).
"""
function split_amount(total::Money, parts::Int)
    parts > 0 || throw(ArgumentError("parts must be positive"))
    q, r = divrem(total.value, parts)
    return Money(q), Money(r)
end

export SCALE, PERMYRIAD, Money, money, scaled, currency, MONEY_ZERO
export permyriad, rate, apply_rate, split_amount
