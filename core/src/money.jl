# Integer fixed-point money.
#
# Money is stored as an Int64 scaled by 10^4 (currency × 10,000), matching the
# four-decimal precision MoneySim uses, but without FixedPointDecimals.
# Rates are parts per million (rate × 1,000,000).

const SCALE = Int64(10_000)
const RATE_SCALE = Int64(1_000_000)
const HALF = SCALE ÷ 2
const RATE_HALF = RATE_SCALE ÷ 2

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

"""
    saturating_add(a::Money, b::Money) -> Money

Add two amounts, clamping at `typemax(Int64)` / `typemin(Int64)` instead of
wrapping. The loan circuit uses this because paper-1 growth runs can exceed the
scaled Int64 range; clamping keeps the series finite and signed.
"""
@inline function saturating_add(a::Money, b::Money)
    s = a.value + b.value
    if b.value > 0 && s < a.value
        return Money(typemax(Int64))
    elseif b.value < 0 && s > a.value
        return Money(typemin(Int64))
    end
    return Money(s)
end

@inline function saturating_add(a::Int64, b::Int64)
    s = a + b
    if b > 0 && s < a
        return typemax(Int64)
    elseif b < 0 && s > a
        return typemin(Int64)
    end
    return s
end

"""    ppm(x::Real) -> Int64

Convert a rate to parts per million (rate × 1,000,000), rounded to an integer.
"""
@inline ppm(x::Real) = round(Int64, x * RATE_SCALE)

"""    permyriad(x::Real) -> Int64

Deprecated alias for [`ppm`](@ref). It now returns parts per million, not
permyriad units.
"""
@inline permyriad(x::Real) = ppm(x)

"""    rate(x::Int64) -> Float64

Convert parts per million back to a rate for reporting.
"""
@inline rate(x::Int64) = Float64(x) / RATE_SCALE

"""
    apply_rate(value::Money, ppm_rate::Int64) -> Money

Apply a ppm rate to an amount. The intermediate product is split so that
`q * rate` cannot overflow for realistic simulation amounts.
"""
@inline function apply_rate(value::Money, ppm_rate::Int64)
    x = value.value
    p = max(ppm_rate, Int64(1))
    if x <= typemax(Int64) ÷ p
        return Money((x * ppm_rate + RATE_HALF) ÷ RATE_SCALE)
    end
    # RATE_SCALE is 100 × SCALE, so the high part is q * p / 100.
    q, rem = divrem(x, SCALE)
    hi = (q ÷ 100) * ppm_rate + ((q % 100) * ppm_rate) ÷ 100
    lo = ((rem * ppm_rate) + RATE_HALF) ÷ RATE_SCALE
    return Money(hi >= (typemax(Int64) >> 1) - lo ?
                 (typemax(Int64) >> 1) : (hi + lo))
end

@inline apply_rate(value::Money, ppm_rate::Real) =
    apply_rate(value, ppm(ppm_rate))

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

export SCALE, RATE_SCALE, HALF, RATE_HALF, Money, money, scaled, currency, MONEY_ZERO
export ppm, permyriad, rate, apply_rate, split_amount, saturating_add
