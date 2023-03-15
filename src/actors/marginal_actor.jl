using Agents

MARGINAL = :marginal

"""
    make_marginal(actor::AbstractActor, needs::Needs)
# Fields
* actor::AbstractActor
* needs::Needs
"""
function make_marginal!(actor::AbstractActor;
                        needs::Needs = Needs(),
                        select_supplier::Function = select_random_supplier)
    add_type!(actor, MARGINAL)
    actor.needs = needs
    actor.select_supplier = select_supplier
    add_behavior!(actor, marginal_behavior)

    return actor
end

function push_usage!(actor::AbstractActor,
                    bp::Blueprint,
                    marginality::Marginality;
                    priority::Integer = 0)
    if hasproperty(actor, :needs)
        push_usage!(actor.needs, bp, marginality, priority = priority)
    end

    return actor
end

function push_want!(actor::AbstractActor,
                    bp::Blueprint,
                    marginality::Marginality;
                    priority::Integer = 0)
    if hasproperty(actor, :needs)
        push_want!(actor.needs, bp, marginality, priority = priority)
    end

    return actor
end

function delete_usage!(actor::AbstractActor,
                    bp::Blueprint;
                    priority::Integer = nothing)
    if hasproperty(actor, :needs)
        delete_usage!(actor.needs, bp, priority = priority)
    end

    return actor
end

function delete_want!(actor::AbstractActor,
                    bp::Blueprint;
                    priority::Integer = nothing)
    if hasproperty(actor, :needs)
        delete_want!(actor.needs, bp, priority = priority)
    end

    return actor
end

function select_random_supplier(model, buyer::AbstractActor, bp::Blueprint)
    condition(blueprint) = agent -> has_stock(agent.stock, blueprint)

    return random_agent(model, condition(bp))
end

function purchase!(model, buyer::AbstractActor, bp::Blueprint, units::Integer)
    supplier = buyer.select_supplier(model, buyer, bp)
    return isnothing(supplier) ? 0 : purchase!(model, buyer, supplier, bp, units)
end

# Behavior functions

function marginal_behavior(model, actor::AbstractActor)
    for dict in (actor.posessions, get_entities(actor.stock))
        for bp in collect(keys(dict))
            for entity in dict[bp]
                if maintenance_due(entity)
                    maintenance!(entity, dict)
                end

                cur_health = health(entity)

                while damaged(entity) && (restore!(entity, dict); health(entity)) > cur_health
                    cur_health = health(entity)
                end
            end
        end
    end

    wants = process_wants(actor.needs, actor.posessions)
    usage = process_usage(actor.needs)

    for want in wants
        bp = want.blueprint
        units = want.units
        total_units = length(actor.posessions[bp]) + units

        # Do not buy items that are in stock
        if stocked(actor.stock, bp)
            push!(actor.posessions, retrieve_stock!(actor.stock, bp, units))
        end

        # Go shop if the stock did not satisfy the want
        while length(actor.posessions[bp]) < total_units && purchase!(model, actor, bp, total_units - length(actor.posessions[bp])) > 0 end
    end

    for use in usage
        i = 0

        for product in collect(actor.posessions[use.blueprint])
            if i < use.units
                use!(product)
                i += 1

                if !usable(product) && !restorable(product)
                    delete!(actor.posessions, product)
                end
            else
                break
            end
        end
    end
end
