# Explicit, deterministic RNG.
#
# The simulation core never uses the global task-local RNG. Every stochastic
# step receives an `Rng`, so a seed fully determines a run and the stream is
# stable across Julia versions.

"""
    Rng(seed::Integer)

A small xorshift64* generator. The state is a single `UInt64`.
"""
mutable struct Rng
    state::UInt64

    function Rng(seed::Integer)
        s = UInt64(seed)
        s == 0 && (s = 0x9E3779B97F4A7C15)
        return new(s)
    end
end

@inline function next_u64!(rng::Rng)::UInt64
    x = rng.state
    x ⊻= x >> 12
    x ⊻= x << 25
    x ⊻= x >> 27
    rng.state = x
    return x * 0x2545f4914f6cdd1d
end

"""
    rand_index(rng::Rng, n::Int) -> Int

Uniform integer in `1:n`.
"""
@inline function rand_index(rng::Rng, n::Int)
    n > 0 || throw(ArgumentError("n must be positive"))
    return Int(rem(next_u64!(rng), UInt64(n))) + 1
end

"""
    rand_unit(rng::Rng) -> Float64

Uniform `Float64` in `[0, 1)`.
"""
@inline function rand_unit(rng::Rng)::Float64
    # 53 random bits, the same width as a Float64 significand.
    return Float64(next_u64!(rng) >> 11) * (1.0 / 9007199254740992.0)
end

@inline rand_bool(rng::Rng, probability::Float64 = 0.5) = rand_unit(rng) < probability

export Rng, next_u64!, rand_index, rand_unit, rand_bool
