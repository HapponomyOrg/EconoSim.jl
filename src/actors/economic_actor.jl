using Agents

Prices = Dict{<:Blueprint, Price}

"""
    EconomicActor - agent representing a full economic actor.

# Fields
* balance::Balance - the balance sheet of the actor.
* posessions::Entities - the entities in personal posession of the actor.
* stock::Stock - the stock held by the actor. The stock is considered to be used for business purposes.
* producers::Set{Producer} - the production facilities of the actor.
* prices::D where D <: Dict{<:Blueprint, Price} - the prices of the products sold by the actor.

After creation, any field can be set on the actor, even those which are not part of the structure. This can come in handy when when specific state needs to be stored with the actor.
"""
@agent struct EconomicActor(Actor) <: AbstractActor
    balance::AbstractBalance = Balance()
    posessions::Entities = Entities()
    stock::Stock = PhysicalStock()
    producers::Set{Producer} = Set{Producer}()
    prices::Prices = Dict{Blueprint, Price}()
end

push_producer!(actor::EconomicActor, producer::Producer) = (push!(actor.producers, producer); actor)
delete_producer!(actor::EconomicActor, producer::Producer) = (delete!(actor.producers, producer); actor)

get_posessions(actor::EconomicActor, bp::Blueprint) = bp in keys(actor.posessions) ? length(actor.posessions[bp]) : 0
get_stock(actor::EconomicActor, bp::Blueprint) = current_stock(actor.stock, bp)

"""
    get_production_output(actor::EconomicActor)

Get the set of all blueprints produced by the actor.
"""
function get_production_output(actor::EconomicActor)
    production = Set{Blueprint}()

    for producer in keys(actor.producers)
        production = union(Set(keys(get_blueprint(producer).batch)), production)
    end

    return production
end

set_price!(actor::EconomicActor, bp::Blueprint, price::Price) = (actor.prices[bp] = price; actor)
get_price(actor::EconomicActor, bp::Blueprint) = haskey(actor.prices, bp) ? actor.prices[bp] : nothing
get_price(model, actor::EconomicActor, bp::Blueprint) = isnothing(get_price(actor, bp)) ? get_price(model, bp) : get_price(actor, bp)

"""
    purchase!(model::ABM, buyer::EconomicActor, seller::EconomicActor, bp::Blueprint, units::Integer, pre_sales::Function...)

Atempt to purchase a number of units from the seller.

* model::ABM
* buyer::EconomicActor
* seller::EconomicActor
* bp::Blueprint
* units::Integer
* pre_sales::Function : functions which need to be executed before a sale takes place. These functions need to have the following signature:
    pre_sale(model::ABM, buyer::EconomicActor, seller::EconomicActor)
"""
function purchase!(model::ABM, buyer::EconomicActor, seller::EconomicActor, bp::Blueprint, units::Integer, pre_sales::Function...)
    available_units = 0
    price = get_price(model, seller, bp)

    if !isnothing(price)
        available_units = min(current_stock(seller.stock, bp), purchases_available(buyer.balance, price, units))

        if available_units > 0
            for pre_sale in pre_sales
                pre_sale(model, buyer, seller)
            end

            buyer.posessions[bp] = union!(buyer.posessions[bp], retrieve_stock!(seller.stock, bp, available_units))
            pay!(buyer.balance, seller.balance, price * available_units)
        end
    end

    return available_units
end

# Behavior functions

"""
    produce_stock!(actor::EconomicActor)

Resupply stocks as needed.
"""
function produce_stock!(model::ABM, actor::EconomicActor)
    stock = actor.stock

    for producer in actor.producers
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
