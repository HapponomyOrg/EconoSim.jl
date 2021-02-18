using Agents

MARGINAL = :marginal

"""
    make_marginal(actor::Actor, needs::Needs)
# Fields
* actor::Actor
* needs::Needs
"""
function make_marginal(actor::Actor, needs::Needs = Needs())
    actor.type = MARGINAL
    actor.needs = needs
    add_behavior!(actor, marginal_behavior)

    return actor
end

function push_usage!(actor::Actor,
                    bp::Blueprint,
                    marginality::Marginality;
                    priority::Integer = 0)
    if hasproperty(actor, :needs)
        push_usage!(actor.needs, bp, marginality, priority = priority)
    end

    return actor
end

function push_want!(actor::Actor,
                    bp::Blueprint,
                    marginality::Marginality;
                    priority::Integer = 0)
    if hasproperty(actor, :needs)
        push_want!(actor.needs, bp, marginality, priority = priority)
    end

    return actor
end

function delete_usage!(actor::Actor,
                    bp::Blueprint;
                    priority::Integer = nothing)
    if hasproperty(actor, :needs)
        delete_usage!(actor.needs, bp, priority = priority)
    end

    return actor
end

function delete_want!(actor::Actor,
                    bp::Blueprint;
                    priority::Integer = nothing)
    if hasproperty(actor, :needs)
        delete_want!(actor.needs, bp, priority = priority)
    end

    return actor
end

function purchase!(model, buyer::Actor, bp::Blueprint, units::Integer)
    condition(blueprint) = agent -> has_stock(agent.stock, blueprint)
    seller = random_agent(model, condition(bp))

    return isnothing(seller) ? 0 : purchase!(model, buyer, seller, bp, units)
end

# Behavior functions

function marginal_behavior(model, actor::Actor)
    for dict in (actor.posessions, actor.stock.stock)
        for bp in collect(keys(dict))
            for entity in dict[bp]
                if maintenance_due(entity)
                    maintenance!(entity, dict)
                end

                cur_health = health(entity)

                while damaged(entity) && health(restore!(entity, dict)) > cur_health
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

                if !usable(product) && !reconstructable(product)
                    delete!(actor.posessions, product)
                end
            else
                break
            end
        end
    end
end
