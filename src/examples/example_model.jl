using Agents
using DataStructures
using EconoSim

# Default properties
SUMSY = :sumsy

# Actor types
CONSUMER = :consumer
BAKER = :baker
TV_MERCHANT = :tv_merchant
GOVERNANCE = :governance

# Consumables
container_ticket = ConsumableBlueprint("Container park ticket")
swim_ticket = ConsumableBlueprint("Swim ticket")
bread = ConsumableBlueprint("Bread")
tv = ProductBlueprint("TV", Restorable(wear = 0.01))

sumsy_data = Dict{Symbol, Float64}(CONSUMER => 0, BAKER => 0, TV_MERCHANT => 0, GOVERNANCE => 0)

"""
    run_example()

Run a pre-configured example model.
"""
function run_example()
    # Mark runtime start
    now = time()
    # Create the Loreco model.
    model = init_loreco_model()

    sb(m) = a -> sumsy_balance(a, m)
    adata = [sb(model)]

    # Execute 300 default steps
    data, _ =run!(model, actor_step!, sumsy_model_step!, 300; adata)

    # Mark runtime end
    done = time() - now

    for actor in allagents(model)
        if has_type(actor, CONSUMER)
            symbol = CONSUMER
        elseif has_type(actor, BAKER)
            symbol = BAKER
        elseif has_type(actor, TV_MERCHANT)
            symbol = TV_MERCHANT
        elseif has_type(actor, GOVERNANCE)
            symbol = GOVERNANCE
        end

        sumsy_data[symbol] = sumsy_data[symbol] + sumsy_balance(actor, model)
    end

    sumsy_data[CONSUMER] = Currency(sumsy_data[CONSUMER] / 380,)
    sumsy_data[BAKER] = Currency(sumsy_data[BAKER] / 15)
    sumsy_data[TV_MERCHANT] = Currency(sumsy_data[TV_MERCHANT] / 20)
    sumsy_data[:contribution] = collected_contributions(model)

    return sumsy_data
end

"""
init_loreco_model(sumsy::SuMSy = SuMSy(2000, 25000, 0.1, 30, seed = 5000),
                consumers::Integer = 380,
                bakers::Integer = 15,
                tv_merchants::Integer = 5)

Creates a pre-configured model.

# Parameters
* sumsy::SuMSy - The SuMSy model to use.
* consumers::Integer - The number of consumers.
* bakers::Integer - The number of bakers.
* tv_merchants::INteger - The number of TV merchants.
"""
function init_loreco_model(sumsy::SuMSy = SuMSy(2000, 25000, 0.1, 30, seed = 5000),
                        consumers::Integer = 380,
                        bakers::Integer = 15,
                        tv_merchants::Integer = 5)
    # Create a standard SuMSy model.
    model = create_single_sumsy_model(sumsy,
                                fixed_contribution,
                                contribution_tiers = 0.05)

    # Add actors.
    add_consumers(model, consumers)
    add_bakers(model, bakers)
    add_tv_merchants(model, tv_merchants)
    add_governance(model, consumers + bakers + tv_merchants)

    return model
end

"""
    add_consumers(model, consumers::Integer)

Add consumers to the model. Consumers do not produce anything. Consumer actors only try to fulfill their needs by attempting to purchase consumables and use them.
"""
function add_consumers(model, consumers::Integer)
    needs = Needs()

    # Add wants. See Needs for details.
    push_want!(needs, container_ticket, [(1, 0.1)])
    push_want!(needs, swim_ticket, [(1, 0.25)])
    push_want!(needs, bread, [(1, 1.0), (2, 0.3), (3, 0.1)])
    push_want!(needs, tv, [(1, 0.4)])

    # Add usages. See Needs for details.
    push_usage!(needs, container_ticket, [(1, 1)])
    push_usage!(needs, swim_ticket, [(1, 1)])
    push_usage!(needs, bread, [(1, 1)])
    push_usage!(needs, tv, [(1, 0.8)])

    for n in 1:consumers
        # Turn the actor into a Loreco actor and add it to the model.
        add_agent!(make_loreco(model, Actor(types = CONSUMER), needs), model)
    end
end

"""
    add_bakers(model, bakers::Integer)

Add bakers to the model. Bakers behave like consumers but also produce goods they sell to other actors.
"""
function add_bakers(model, bakers::Integer)
    needs = Needs()
    push_want!(needs, container_ticket, [(1, 0.3)])
    push_want!(needs, swim_ticket, [(1, 0.2)])
    push_want!(needs, bread, [(1, 1.0), (2, 0.3)])
    push_want!(needs, tv, [(1, 0.6)])

    push_usage!(needs, container_ticket, [(1, 1)])
    push_usage!(needs, swim_ticket, [(1, 1)])
    push_usage!(needs, bread, [(1, 1)])
    push_usage!(needs, tv, [(1, 0.5)])

    # Set the price of bread.
    set_price!(model, bread, 5)

    # Create a producer that produces bread. A bakery produces bread without any input.
    bakery = ProducerBlueprint("Bakery", batch = Dict(bread => 1))

    for n in 1:bakers
        # Turn the actor into a Loreco actor.
        baker = make_loreco(model, Actor(types = BAKER, producers = [Producer(bakery)]), needs)

        # Set the minimum stock of bread. This triggers production.
        min_stock!(baker.stock, bread, 35)
        add_agent!(baker, model)
    end
end

function add_tv_merchants(model, tv_merchants::Integer)
    needs = Needs()
    push_want!(needs, container_ticket, [(1, 1)])
    push_want!(needs, swim_ticket, [(1, 1)])
    push_want!(needs, bread, [(1, 0.3), (2, 0.1), (3, 0.05)])
    push_want!(needs, tv, [(1, 1)])

    push_usage!(needs, container_ticket, [(1, 0.4)])
    push_usage!(needs, swim_ticket, [(1, 0.3)])
    push_usage!(needs, bread, [(1, 1)])
    push_usage!(needs, tv, [(1, 0.9)])

    set_price!(model, tv, 1000)
    tv_factory = ProducerBlueprint("TV factory", batch = Dict(tv => 1))

    for n in 1:tv_merchants
        tv_merchant = make_loreco(model, Actor(types = TV_MERCHANT, producers = [Producer(tv_factory)]), needs)

        min_stock!(tv_merchant.stock, tv, 10)
        add_agent!(tv_merchant, model)
    end
end

function add_governance(model, citizens::Integer)
    set_price!(model, container_ticket, 10)
    set_price!(model, swim_ticket, 3)

    container_park = ProducerBlueprint("Container park", batch = Dict(container_ticket => 1))
    swimming_pool = ProducerBlueprint("Swimming pool", batch = Dict(swim_ticket => 1))

    governance = make_loreco(model, Actor(types = GOVERNANCE, producers = [Producer(container_park), Producer(swimming_pool)]))

    min_stock!(governance.stock, container_ticket, citizens)
    min_stock!(governance.stock, swim_ticket, citizens)
    set_sumsy_active!(governance, model, false)
    add_agent!(governance, model)
end

function sumsy_price(model, bp::Blueprint)
    price(model)[SUMSY_DEP]
end

function EconoSim.set_price!(model, bp::Blueprint, sumsy_price::Real, euro_price::Real = 0)
    price = Price()
    price[SUMSY_DEP] = sumsy_price
    price[DEPOSIT] = euro_price

    return set_price!(model, bp, price)
end

"""
    make_loreco(model, actor, needs = nothing)

Turn the actor into a Loreco actor.
"""
function make_loreco(model, actor, needs = nothing)
    if !has_type(actor, CONSUMER)
        # Consumers do not produce anything and thus do not need the production behavior. All other actors engage in production before the agents are activated individually.
        add_model_behavior!(actor, produce_stock!)
    end

    # If the actor has needs, add marginal behavior to its behavior functions.
    return isnothing(needs) ? actor : make_marginal(actor, needs)
end
