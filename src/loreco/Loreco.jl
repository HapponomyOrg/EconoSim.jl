"""
    The Loreco module is a wrapper module which is pre-configured to run simulations on the Econo_Sim framework.

    For detailed information on how to cinfigure actors, see the Econo_Sim module.
"""
module Loreco
    include("loreco_model.jl")
    export CONSUMER, BAKER, TV_MERCHANT, GOVERNANCE
    export init_loreco_model, create_consumer, create_merchant, set_price!
    export loreco_model_step!, loreco_agent_step!
    export init_default_model
    export sumsy_balance
end
