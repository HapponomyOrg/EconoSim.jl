abstract type Lifecycle end
abstract type Blueprint end

"""
    Entity

All implementations of Entity must have the following fields:
* id::UUID
* blueprint::Blueprint
* health::Health
"""
abstract type Entity end
abstract type Enhancer <: Entity end
