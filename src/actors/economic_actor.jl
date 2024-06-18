using Agents

Prices = Dict{<:Blueprint, Price}

"""
    EconomicAssets - data structure for storing the economic assets and parameters of an actor.

# Fields
* posessions::Entities - the entities in personal posession of the assets.
* stock::Stock - the stock held by the assets. The stock is considered to be used for business purposes.
* producers::Set{Producer} - the production facilities of the assets.
* prices::D where D <: Dict{<:Blueprint, Price} - the prices of the products sold by the assets.

After creation, any field can be set on the actor, even those which are not part of the structure. This can come in handy when when specific state needs to be stored with the assets.
"""
struct EconomicAssets
    posessions::Entities
    stock::Stock
    producers::Set{Producer}
    prices::Prices
end

"""
    make_economic_actor(actor::BalanceActor) - Add economic assets and parameters to an actor.
# Fields
* actor::BalanceActor
"""
function make_economic_actor!(actor:: BalanceActor;
                                posessions::Entities = Entities(),
                                stock::Stock = PhysicalStock(),
                                producers::Set{Producer} = Set{Producer}(),
                                prices::Prices = Dict{Blueprint, Price}())
    actor.economic_assets = EconomicAssets(posessions, stock, producers, prices)

    return actor
end

economic_assets(actor::BalanceActor) = actor.economic_assets
posessions(actor::BalanceActor) = economic_assets(actor).posessions
stock(actor::BalanceActor) = economic_assets(actor).stock
producers(actor::BalanceActor) = economic_assets(actor).producers
prices(actor::BalanceActor) = economic_assets(actor).prices

push_producer!(actor::BalanceActor, producer::Producer) = (push!(producers(actor), producer); actor)
delete_producer!(actor::BalanceActor, producer::Producer) = (delete!(producers(actor), producer); actor)

get_posessions(actor::BalanceActor, bp::Blueprint) = bp in keys(posessions(actor)) ? length(posessions(actor)[bp]) : 0
get_stock(actor::BalanceActor, bp::Blueprint) = current_stock(stock(actor), bp)

"""
    get_production_output(actor::BalanceActor)

Get the set of all blueprints produced by the actor.
"""
function get_production_output(actor::BalanceActor)
    production = Set{Blueprint}()

    for producer in keys(producers(actor))
        production = union(Set(keys(get_blueprint(producer).batch)), production)
    end

    return production
end

set_price!(actor::BalanceActor, bp::Blueprint, price::Price) = (prices(actor)[bp] = price; actor)
get_price(actor::BalanceActor, bp::Blueprint) = haskey(prices(actor), bp) ? prices(actor)[bp] : nothing
get_price(model, actor::BalanceActor, bp::Blueprint) = isnothing(get_price(actor, bp)) ? get_price(model, bp) : get_price(actor, bp)

"""
    purchase!(model::ABM, buyer::EconomicAssets, seller::EconomicAssets, bp::Blueprint, units::Integer, pre_sales::Function...)

Atempt to purchase a number of units from the seller.

* model::ABM
* buyer::EconomicAssets
* seller::EconomicAssets
* bp::Blueprint
* units::Integer
* pre_sales::Function : functions which need to be executed before a sale takes place. These functions need to have the following signature:
    pre_sale(model::ABM, buyer::BalanceActor, seller::BalanceActor)
"""
function purchase!(model::ABM, buyer::Actor, seller::Actor, bp::Blueprint, units::Integer, pre_sales::Function...)
    available_units = 0
    price = get_price(model, seller, bp)

    if !isnothing(price)
        available_units = min(current_stock(stock(seller), bp), purchases_available(get_balance(buyer), price, units))

        if available_units > 0
            for pre_sale in pre_sales
                pre_sale(model, buyer, seller)
            end

            posessions(buyer)[bp] = union!(posessions(buyer)[bp], retrieve_stock!(stock(seller), bp, available_units))
            pay!(get_balance(buyer), get_balance(seller), price * available_units)
        end
    end

    return available_units
end

# Behavior functions

"""
    produce_stock!(model::ABM, actor::BalanceActor)

Resupply stocks as needed.
"""
function produce_stock!(model::ABM, actor::BalanceActor)
    stock = stock(actor)

    for producer in producers(actor)
        p_bp = get_blueprint(producer)
        min_batches = 0
        max_batches = INF

        for bp in keys(p_bp.batch)
            batch = p_bp.batch[bp]

            min_units = max(min_stock(stock, bp) - current_stock(stock, bp), 0)
            min_batches = max(min_batches, Int(round(min_units / batch, RoundUp)))

            max_units = max(max_stock(stock, bp) - current_stock(stock, bp), 0)
            max_batches = min(max_batches, Int(round(max_units / batch, RoundDown)))
        end

        batches = max(min_batches, max_batches)

        for i in 1:batches
            products = produce!(producer, stock.stock)

            if !isempty(products)
                add_stock!(stock, products)
            else
                break
            end
        end
    end

    return actor
end
