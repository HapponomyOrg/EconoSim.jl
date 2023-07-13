using FixedPointDecimals
using Intervals
using Todo

"""
    Percentage
A float which remains between 0 and 1, representing 0% - 100%.
"""
struct Percentage <: Real
    value::Float64
    Percentage(x) = x < 0 ? new(0) : x > 1 ? new(1) : new(x)
end

Base.show(io::IO, x::Percentage) = print(io, "Percentage($(round(x.value, digits = 6) * 100)%)")

Base.convert(::Type{Percentage}, x::Real) = Percentage(x)
Base.convert(::Type{Percentage}, x::Percentage) = x
Base.convert(::Type{Float64}, x::Percentage) = x.value

Base.promote_rule(::Type{T}, ::Type{Percentage}) where T <: Real = Percentage
Base.round(x::Percentage; digits::Integer = 6, base = 10) = Percentage(round(value(x), digits = digits, base = base))

"""
    Health
Mutable struct holding health, expressed in percentages between 0% and 100%.
"""
mutable struct Health
    current::Percentage
    Health(current=1) = new(current)
end

Base.round(x::Health; digits::Integer = 6, base = 10) = Health(round(value(x), digits = digits, base = base))

Base.convert(::Type{Health}, x::Real) = Health(x)
Base.convert(::Type{Health}, x::Health) = x

value(x::Percentage) = x.value
value(x::Health) = value(x.current)

import Base: +, -, *, /, <, >, <=, >=, ==, max, min

for type in (Percentage, Health)
    for op in (:+, :-, :max, :min)
        eval(quote
            Base.$op(x::$type, y::$type) = $type($op(value(x), value(y)))
            Base.$op(x::$type, y::Real) = $type($op(value(x), y))
            Base.$op(x::Real, y::$type) = $type($op(x, value(y)))
        end)
    end

    for op in (:*, :/)
        eval(quote
            Base.$op(x::$type, y::$type) = $op(value(x), value(y))
            Base.$op(x::$type, y::Real) = $op(value(x), y)
            Base.$op(x::Real, y::$type) = $op(x, value(y))
        end)
    end

    for op in (:<, :<=, :>, :>=)
        eval(quote
            Base.$op(x::$type, y::$type) = $op(round(value(x), digits=6), round(value(y), digits=6))
            Base.$op(x::$type, y::Real) = $op(round(value(x), digits=6), round(y, digits=6))
            Base.$op(x::Real, y::$type) = $op(round(x, digits=6), round(value(y), digits=6))
        end)
    end

    eval(quote
        ==(x::$type, y::$type) = round(value(x), digits=6) == round(value(y), digits=6)
        ==(x::$type, y::Real) = round(value(x), digits=6) == round(y, digits=6)
        ==(x::Real, y::$type) = round(x, digits=6) == round(value(y), digits=6)
    end)
end

*(x::Health, y::Percentage) = Health(round(value(x) * value(y), digits = 6))
*(x::Percentage, y::Health) = Health(round(value(x) * value(y), digits = 6))

/(x::Health, y::Percentage) = Health(round(value(x) / value(y), digits = 6))
/(x::Percentage, y::Health) = Health(round(value(x) / value(y), digits = 6))

"""
    Fixed
Convenience type for working with fixed point decimals.
"""
Fixed(digits::Integer) = FixedDecimal{Int128, digits}

"""
    Currency
Convenience type for working with currencies.
"""
Currency = Fixed(2)

todo"Fix operations type casting"

#for op in (:+, :-, :*, :/, :max, :min)
#    eval(quote
#        Base.$op(x::Currency, y::Real) = Currency(Base.$op(Float64(x), y))
#        Base.$op(x::Real, y::Currency) = Currency(Base.$op(x, Float64(y)))
#        Base.$op(x::Currency, y::Percentage) = Currency(Base.$op(Float64(x), y))
#        Base.$op(x::Percentage, y::Currency) = Currency(Base.$op(x, Float64(y)))
#    end)
#end

LeftInterval{T} = Interval{T, Closed, Open}
RightInterval{T} = Interval{T, Open, Closed}
ClosedInterval{T} = Interval{T, Closed, Closed}
