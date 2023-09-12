using EconoSim

set_currency_precision!(4)

include("finance_test.jl")
include("production_test.jl")
include("utilities_test.jl")
include("models_test.jl")
include("actors_test.jl")

# Testing whether everything works with other precision
set_currency_precision!(6)

include("finance_test.jl")
include("production_test.jl")
include("utilities_test.jl")
include("models_test.jl")
include("actors_test.jl")