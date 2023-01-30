# EconoSim

## Simulation tools for agent based economic simulation.

This package provides a configurable framework for building agent based economic simulations. The package is subdivided in modules which each fulfill a specific functionality.

### Production module
This module provides the tools to set up a production simulation.
Blueprints serve as templates for the production of entities. Each Entity inherits the aspects of the blueprint but can be regarded as a separate unit.

Entities have a unique id and a health status which ranges from 0 to 1. An Entity with health 0 is destroyed and can no longer be used. Destroyed entities might produce waste if it is configured in the blueprint.

The production module defines a number of pre-defined blueprints:
* ConsumableBlueprint: these are used for products that can be used once.
* DecayableBlueprint: these are for products that decay with each use.
* ProductBlueprint: these are used for products with a more complex lifecycle. These blueprints can be configured in such a way that the resulting products wear over time but can also be repaired.
* ProducerBlueprint: These are blueprints for producers. Producers are configured with input and output specifications, thereby consuming the input and producing the output. Their lifecycle configuration is similar to that of ProductBlueprint.

### Finance module
The finance module provides basic building blocks for financial simulations. A balance sheet has been implemented, according to the double entry bookkeeping model. All entries on a balance are quantified as Currency, which is a number with two digits after the decimal point.
Equity of a balance is recalculated after each operation on the balance.

This module provides code for simulating interest bearing loans. These loans can be bank loans or peer to peer loans. With bank loans, money/debt creation on issuing the loan and money/debt destruction on payoff of the loan is implemented.

An alternative monetary model, the Sustainable Money System, or SuMSy for short is implemented. The model allows for ex-nihilo debt-less money creation which has the purpose to serve as a guaranteed income for living individuals. Money destruction is implemented by charging demurrage on account balances.
Full details on this monetary model can be found at [Happonomy - The Sustainable Money System](https://www.happonomy.org/sustainable-money-system/)

Code for multi currency prices has been included. These can be used for simulations where complementary monetary systems are present.

### Actors module
The framework builds on the Agents.jl module and expands it. An Actor, which extends AbstractAgent, is implemented as the basic agent to be used in simulations. This Actor implements extendable and changeable behavior functionality.

MarginalActor is an Actor seeded with basic marginal utility behavior. Each actor can be configured to acquire products according to a marginal need. Consumption of these products can be configured in a similar manner.

### Models module
A basic, extendable model for simulations is provided along with a model for simulations using the SuMSy monetary model.