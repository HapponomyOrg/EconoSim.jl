# Integer fixed-point money.
#
# Money is stored as an Int64 scaled by 10^4 (currency × 10,000), matching the
# four-decimal precision MoneySim uses, but without FixedPointDecimals.
# Rates are parts per million (rate × 1,000,000).

const SCALE = Int64(10_000)
const RATE_SCALE = Int64(1_000_000)
const HALF = SCALE ÷ 2
const RATE_HALF = RATE_SCALE ÷ 2

# Overflow policy: checked by default; saturating is an explicit browser mode.
const OVERFLOW_ERROR = Int64(0)
const OVERFLOW_SATURATE = Int64(1)
const OVERFLOW_MODE = Int64[OVERFLOW_ERROR]

@inline overflow_mode() = OVERFLOW_MODE[1]

"""
    set_overflow_mode!(mode)

Select `OVERFLOW_ERROR` (default) or `OVERFLOW_SATURATE` for subsequent money
arithmetic. The wasm browser build sets `OVERFLOW_SATURATE` explicitly.
"""
function set_overflow_mode!(mode::Integer)
    (mode == OVERFLOW_ERROR || mode == OVERFLOW_SATURATE) ||
        throw(ArgumentError("invalid overflow mode: $mode"))
    OVERFLOW_MODE[1] = Int64(mode)
    return nothing
end

@inline function _overflow_value(sign::Int)
    overflow_mode() == OVERFLOW_SATURATE ||
        throw(OverflowError("Money arithmetic overflow"))
    return sign > 0 ? typemax(Int64) : typemin(Int64)
end

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

@inline function Base.:+(a::Money, b::Money)
    s = a.value + b.value
    if (b.value > 0 && s < a.value) || (b.value < 0 && s > a.value)
        return Money(_overflow_value(b.value > 0 ? 1 : -1))
    end
    return Money(s)
end

@inline function Base.:-(a::Money, b::Money)
    s = a.value - b.value
    if (b.value < 0 && s < a.value) || (b.value > 0 && s > a.value)
        return Money(_overflow_value(b.value < 0 ? 1 : -1))
    end
    return Money(s)
end

@inline function Base.:-(a::Money)
    a.value == typemin(Int64) && return Money(_overflow_value(1))
    return Money(-a.value)
end

@inline function Base.:*(a::Money, b::Integer)
    b == 0 && return MONEY_ZERO
    a.value == typemin(Int64) && b == -1 &&
        return Money(_overflow_value(1))
    product = a.value * Int64(b)
    if div(product, Int64(b)) != a.value
        sign = ((a.value < 0) ⊻ (b < 0)) ? -1 : 1
        return Money(_overflow_value(sign))
    end
    return Money(product)
end

@inline Base.:*(b::Integer, a::Money) = a * b
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

Deprecated alias for `a + b`. The active overflow mode decides whether an
overflow throws or saturates.
"""
@inline saturating_add(a::Money, b::Money) = a + b

@inline saturating_add(a::Int64, b::Int64) = a + b

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
    div_round_nearest(a::Int64, b::Int64) -> Int64

`a / b` rounded half to even, using floored division like `FixedPointDecimals`.
`b` must be positive. Use this wherever main EconoSim divides a `Currency` by
an `Integer`, which rounds instead of truncating.
"""
@inline function div_round_nearest(a::Int64, b::Int64)
    q, r = fldmod(a, b)
    half = b >> 1
    if iseven(b) && r == half
        return isodd(q) ? q + 1 : q
    elseif r > half
        return q + 1
    end
    return q
end

"""
    apply_rate(value::Money, ppm_rate::Int64) -> Money

Apply a ppm rate to an amount. The intermediate product is split so that
`q * rate` cannot overflow for realistic simulation amounts.
"""
@inline function _round_rate(numerator::Int64)
    negative = numerator < 0
    magnitude = negative ? -numerator : numerator
    quotient, remainder = divrem(magnitude, RATE_SCALE)
    if 2 * remainder > RATE_SCALE ||
       (2 * remainder == RATE_SCALE && isodd(quotient))
        quotient += 1
    end
    return negative ? -quotient : quotient
end

@inline function apply_rate(value::Money, ppm_rate::Int64)
    x = value.value
    p = max(ppm_rate, Int64(1))
    if x <= typemax(Int64) ÷ p
        return Money(_round_rate(x * ppm_rate))
    end
    # RATE_SCALE is 100 × SCALE, so the high part is q * p / 100.
    q, rem = divrem(x, SCALE)
    hi = (q ÷ 100) * ppm_rate + ((q % 100) * ppm_rate) ÷ 100
    lo = ((rem * ppm_rate) + RATE_HALF) ÷ RATE_SCALE
    hi >= typemax(Int64) - lo && return Money(_overflow_value(1))
    return Money(hi + lo)
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
export OVERFLOW_ERROR, OVERFLOW_SATURATE, overflow_mode, set_overflow_mode!
export ppm, permyriad, rate, apply_rate, split_amount, saturating_add
export div_round_nearest
