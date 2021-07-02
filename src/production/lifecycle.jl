using DataStructures
using Intervals

@enum Direction up down

# Convenience aliases
ThresholdInput = Union{<: AbstractVector{<:Tuple{<:Real, <:Real}},
                <: AbstractSet{<:Tuple{<:Real, <:Real}}}
Thresholds = SortedSet{Tuple{Interval, Float64}}

Thresholds(input::ThresholdInput, direction::Direction) = convert_thresholds(input, direction)

"""
    restorable(lifecycle::Union{Lifecycle, Nothing})

Indicates whether or not restoration is possible.
"""
restorable(lifecycle::Union{Lifecycle, Nothing}, health::Health) = false

"""
    get_maintenance_interval(lifecycle::Union{Lifecycle, Nothing})

Return the maintenance interval
"""
get_maintenance_interval(lifecycle::Union{Lifecycle, Nothing}) = INF

"""
    maintenance_due(lifecycle::Union{Lifecycle, Nothing}, uses::Integer)

# Fields
* lifecycle
* uses

Return whether is not maintenance is due based on the number of uses.
"""
maintenance_due(lifecycle::Union{Lifecycle, Nothing}, uses::Integer) = uses >= get_maintenance_interval(lifecycle)

"""
    maintain!(lifecycle::Union{Lifecycle, Nothing}, health::Health, resources::Entities)

# Fields
* lifecycle
* health
* resources

Returns weather or not maintenance was succesful and waste products from used resources, if any.
"""
maintain!(lifecycle::Union{Lifecycle, Nothing}, resources::Entities) = (false, Entities())
overuse!(lifecycle::Union{Lifecycle, Nothing}, health::Health) = health
wear!(lifecycle::Union{Lifecycle, Nothing}, health::Health) = health

"""
    damage(lifecycle::Union{Lifecycle, Nothing}, amount::Real)

Returns adjusted health.
"""
function damage!(lifecycle::Union{Lifecycle, Nothing}, health::Health, amount::Real)
    health.current -= amount

    return health
end

"""
    restore(lifecycle::Union{Lifecycle, Nothing}, resources::Entities)

Returns the adjusted health and the waste products from used resources, if any.
"""
restore!(lifecycle::Union{Lifecycle, Nothing}, health::Health, resources::Entities) = Entities()

"""
    Restorable

Indicates a lifecycle with restorability, i.e. the entity can recover from damage.
Thresholds determine the multiplier for health at and below the threshold.

# Fields
* `damage_thresholds`: These are tuples, ordered by percentage, holding damage multipliers. The applied multiplier corresponds with the lowest threshold which is higher than the health of the entity.
* `restoration_thresholds`: These are tuples, ordered by percentage, holding restoration multipliers. The applied multiplier corresponds with the lowest threshold which is higher than the health of the entity.
* `wear`: damage which occurs from each use. Succeptable to multipliers.

# Example
`
Restorable
    damage_thresholds = [(70.0%, 0.5), (100.0%, 0.2)]
    restoration_thresholds = [(40.0%, 0.0), (70.0%, 0.2), (100.0%, 0.3)]
`
When 1 damage is done it results in 0.2 damage actually being applied. Should health drop to 70% or less, then 0.5 damage would be applied. This indicates the robustness at various levels of damage.

When 1 damage is restored it results in 0.3 damage actually being restored. Should health drop to 40% or below no damage is being restored. This indicates restorability. The last tier indicates a level of damage beyond which no restoration is possible anymore.
"""
struct Restorable <: Lifecycle
    damage_thresholds::Thresholds
    restoration_thresholds::Thresholds
    restore_res::Blueprints
    restore_tools::Blueprints
    restore::Float64
    maintenance_interval::Int64
    maintenance_res::Blueprints
    maintenance_tools::Blueprints
    neglect_damage::Float64
    wear::Float64
    Restorable(;
        damage_thresholds::ThresholdInput=[(1, 1)],
        restoration_thresholds::ThresholdInput=[(0, 1)],
        restore_res::Blueprints = Dict{Blueprint,Int64}(),
        restore_tools::Blueprints = Dict{Blueprint,Int64}(),
        restore::Real = 0,
        maintenance_interval::Integer = INF,
        maintenance_res::Blueprints = Dict{Blueprint,Int64}(),
        maintenance_tools::Blueprints = Dict{Blueprint,Int64}(),
        neglect_damage::Real = 0,
        wear::Real = 0) = new(
                    convert_thresholds(damage_thresholds, down),
                    convert_thresholds(restoration_thresholds, up),
                    restore_res,
                    restore_tools,
                    restore,
                    maintenance_interval,
                    maintenance_res,
                    maintenance_tools,
                    neglect_damage,
                    wear)
end

"""
    convert_thresholds

Converts threshold input into Threshold intervals.
Intervals are created for each tuple in the input. All intervals are halfopen.
When the direction is up they are closed on the lower bound and open on the upper bound.
When the direction is down they are open on the lower bound and closed on the upper bound.
The lowest bound is always 0 and the highest bound is always 1.
The edges 0 and 1 are always closed.
"""
function convert_thresholds(thresholds_input::ThresholdInput, direction::Direction)
    thresholds_input = SortedSet(thresholds_input)
    thresholds = Thresholds()
    IntervalType = direction == up ? LeftInterval : RightInterval

    if isempty(thresholds_input)
        push!(thresholds, (ClosedInterval(0, 1), 1))
    else
        if length(thresholds_input) == 1
            push!(thresholds, (ClosedInterval(0, 1), first(thresholds_input)[2]))
        else
            index = 1
            lower_bound = 0
            upper_bound = 0

            for t in thresholds_input
                upper_bound = t[1]
                multiplier = t[2]

                if index == 1 && direction == down
                    push!(thresholds, (ClosedInterval(0, upper_bound), multiplier))
                elseif index == length(thresholds_input) && direction == up
                    push!(thresholds, (ClosedInterval(lower_bound, 1), multiplier))
                else
                    push!(thresholds, (IntervalType(lower_bound, upper_bound), multiplier))
                    lower_bound = upper_bound
                end

                index += 1
            end
        end
    end

    return thresholds
end

function restorable(lifecycle::Restorable, health::Health)
    if lifecycle.restore == 0
        return false
    else
        ok = false

        for threshold in lifecycle.restoration_thresholds
            if health in threshold[1] && threshold[2] != 0
                ok = true
                break
            end
        end

        return ok
    end
end

get_maintenance_interval(lifecycle::Restorable) = lifecycle.maintenance_interval
overuse!(lifecycle::Restorable, health::Health) = damage!(lifecycle, health, lifecycle.neglect_damage)

function damage!(lifecycle::Restorable, health::Health, change::Real)
    return change_health!(lifecycle, health, change, down)
end

function restore!(lifecycle::Restorable, health::Health, resources::Entities)
    result = extract!(resources, lifecycle.restore_res, lifecycle.restore_tools)

    if result[1]
        change_health!(lifecycle, health, lifecycle.restore, up)
    end

    return result
end

function maintain!(lifecycle::Restorable, resources::Entities)
    return extract!(resources, lifecycle.maintenance_res, lifecycle.maintenance_tools)
end

function wear!(lifecycle::Restorable, health::Health)
    return damage!(lifecycle, health, lifecycle.wear)
end

function extract!(source::Entities, resource_req::Blueprints, tool_req::Blueprints)
    resources = Set()
    tools = Set()
    extracted = true

    for t in ((resource_req, resources), (tool_req, tools))
        requirements = t[1]
        entities = t[2]

        if extracted && !isempty(requirements)
            for bp in keys(requirements)
                if bp in keys(source) && length(source[bp]) >= requirements[bp]
                    union!(entities, extract(source[bp], requirements[bp], usable))
                else
                    extracted = false
                end
            end
        end
    end

    wastes = Entities()

    if extracted
        for todo in ((resources, destroy!), (tools, use!))
            entities = todo[1]
            action = todo[2]
            to_remove = Set{Entity}()

            for entity in entities
                merge!(wastes, action(entity))

                if !usable(entity) && !restorable(entity)
                    push!(to_remove, entity)
                end
            end

            for entity in to_remove
                delete!(source, entity)
            end
        end
    end

    return extracted, wastes
end

function change_health!(lifecycle::Restorable, health::Health, change::Real, direction::Direction)
    if direction == up
        thresholds = collect(lifecycle.restoration_thresholds)
    else
        thresholds = reverse!(collect(lifecycle.damage_thresholds))
    end

    change_to_process = change
    real_change = 0

    for threshold in thresholds
        interval = threshold[1]
        multiplier = threshold[2]

        if change_to_process > 0 && (health + real_change) in interval
            max_change = direction == up ? last(interval) - health : health - first(interval)
            interval_change = min(max_change, change_to_process * multiplier)
            change_to_process -= interval_change / multiplier
            real_change += interval_change
        else
            break
        end
    end

    health.current += direction == up ? value(real_change) : -value(real_change)

    return health
end
