function extract(set::Set, num_elements::Integer, condition::Function = truecondition)
    result = Set()
    i = 0

    for element in set
        if i < num_elements && condition(element)
            push!(result, element)
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
