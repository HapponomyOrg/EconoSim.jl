abstract type Lifecycle end
abstract type Blueprint end
abstract type LifecycleBlueprint <: Blueprint end
abstract type RestorableBlueprint <: LifecycleBlueprint end

Blueprints = Dict{<:Blueprint,Int64}

"""
    Entity

All implementations of Entity must have the following fields:
* id::UUID
* blueprint::Blueprint
* health::Health
"""
abstract type Entity end
abstract type RestorableEntity <: Entity end
abstract type Enhancer <: Entity end
