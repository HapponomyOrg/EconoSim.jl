using Agents

"""
MonetaryActor - agent representing a monetary actor.

# Fields
* balance::Balance - the balance sheet of the actor.

After creation, any field can be set on the actor, even those which are not part of the structure. This can come in handy when when specific state needs to be stored with the actor.
"""
@agent struct MonetaryActor(Actor) <: AbstractActor
    balance::AbstractBalance = Balance()
end