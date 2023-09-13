function extract(set::Set, num_elements::Integer, condition::Function = truecondition)
    result = Set()
    i = 0

    for element in set
        if i < num_elements && condition(element)
            push!(result, element)
            i += 1
        else
            break
        end
    end

    return result
end

function delete_element!(array::AbstractArray, element)
    deleteat!(array, findall(x -> x == element, array))
end

function delete_element!(set::AbstractSet, element)
    delete!(set, element)
end

is_left_closed(interval::AbstractInterval{T,L,R}) where {T,L,R} = L === Closed
is_right_closed(interval::AbstractInterval{T,L,R}) where {T,L,R} = R === Closed

is_left_open(interval::AbstractInterval{T,L,R}) where {T,L,R} = L === Open
is_right_open(interval::AbstractInterval{T,L,R}) where {T,L,R} = R === Open

is_left_unbounded(interval::AbstractInterval{T,L,R}) where {T,L,R} = L === Unbounded
is_right_unbounded(interval::AbstractInterval{T,L,R}) where {T,L,R} = R === Unbounded

function set_currency_precision!(precision::Int)
    global Currency
    global CUR_MAX
    global CUR_MIN
    global CUR_0
    
    Currency = Fixed(precision)

    CUR_MAX = typemax(Currency)
    CUR_MIN = typemin(Currency)
    CUR_0 = Currency(0)
end