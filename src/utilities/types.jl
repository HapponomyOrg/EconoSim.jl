struct Percentage <: Real
    value::Float64
    Percentage(x, precision::Integer=6) = x < 0 ? new(0) : x > 1 ? new(1) : new(round(x, digits=precision))
end

Base.show(io::IO, x::Percentage) = print(io, "Percentage($(x.value * 100)%)")

Base.convert(::Type{Percentage}, x::Real) = Percentage(x)
Base.convert(::Type{Percentage}, x::Percentage) = x

Base.promote_rule(::Type{T}, ::Type{Percentage}) where T <: Real = Percentage
Base.round(x::Percentage; digits::Integer = 6, base = 10) = Percentage(round(value(x), digits = digits, base = base))

mutable struct Health
    current::Percentage
    Health(current=1) = new(current)
end

Base.round(x::Health; digits::Integer = 6, base = 10) = Health(round(value(x), digits = digits, base = base))

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
            Base.$op(x::$type, y::$type) = $type($op(value(x), value(y)))
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
