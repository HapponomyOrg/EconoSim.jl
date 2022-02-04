using Agents

# Model behaviors

function update_stock!(model)
    for actor in allagents(model)
        if !isempty(actor.producers)
            produce_stock!(model, actor)
        end
    end
end

# Actor behaviors

