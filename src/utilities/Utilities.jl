
include("types.jl")
export Percentage, Health, value, num_entities
export Fixed, Currency
export LeftInterval, RightInterval, ClosedInterval

include("functions.jl")
export extract, delete_element!

include("constants.jl")
export INF, CUR_MIN, CUR_MAX
