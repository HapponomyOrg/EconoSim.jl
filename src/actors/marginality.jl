using DataStructures

"""
    Marginality - a progressive marginal use structure.

* marginality::Vector{Tuple{Int64, Percentage}} - a sorted list of tuples consisting of a number of units and a probability resulting in an extra unit if the number of available units is below the indicated number.
"""
Marginality = SortedSet{Tuple{Int64, Percentage}}

"""
    process(marginality::Marginality, units::Int64)

Determines the marginal number of units, given a current number of units.
As long as the check for a supplementary unit returns true, another check will be executed for yet another unit.

# Example:
Given a marginality: [(2, 1.0), (5, 0.5)]

Tuples denote a number of units and the probability an extra unit if the available number of units is less than the given number.
In the example above the probability for the first unit is 100% if no units are available.
A check for a second unit is executed and since the probability for this is also 100%, a check for a third unit is executed.
The probability for a third unit is 50% (2 units are available thus the next tuple is used). If this check results in a third unit, a check for a fourth unit will be made and so on.
Once 5 units are available the check will always return false in this example and therefor the maximum number of units is 5.

# Returns
The number of marginal units.
"""
function process(marginality::Marginality, units::Int64 = 0)
    total_units = units

    for entry in marginality
        done = false

        while total_units < entry[1]
            if rand() <= entry[2]
                total_units += 1
            else
                done = true
                break
            end
        end

        if done
            break
        end
    end

    return total_units - units
end
