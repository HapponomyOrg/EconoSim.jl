using Test
using .EconoSim

@testset "Restorable" begin
    bp = ConsumableBlueprint("C")

    r = Restorable()
    @test r.damage_thresholds == Thresholds([(0, 0), (1, 1.0)])
    @test r.restoration_thresholds == Thresholds([(0, 0), (1, 1.0)])
    @test r.restore == 0
    @test r.maintenance_interval == INF
    @test isempty(r.maintenance_res)
    @test r.neglect_damage == 0
    @test r.wear == 0

    r = Restorable(
        damage_thresholds = [(1, 1), (0.8, 2)],
        restoration_thresholds = [(1, 2), (0.6, 1), (0.2, 0)],
        restore = 0.1,
        maintenance_interval = 10,
        maintenance_res = Dict([bp => 1]),
        neglect_damage = 0.5,
        wear = 0.1,
    )
    @test r.damage_thresholds == Thresholds([(1, 1), (0.8, 2), (0, 0)])
    @test r.restoration_thresholds == Thresholds([(1, 2), (0.6, 1), (0.2, 0)])
    @test r.restore == 0.1
    @test r.maintenance_interval == 10
    @test length(r.maintenance_res) == 1
    @test (bp => 1) in r.maintenance_res
    @test r.neglect_damage == 0.5
    @test r.wear == 0.1
end

@testset "Consumable" begin
    name = "Food"
    bp = ConsumableBlueprint(name)
    @test get_lifecycle(bp) == nothing
    @test get_maintenance_interval(bp) == INF

    f1 = Consumable(bp)
    @test get_blueprint(f1).name == name
    @test get_name(f1) == name
    @test typeof(id(f1)) == Base.UUID
    @test typeof(type_id(f1)) == Base.UUID
    @test id(f1) != type_id(f1)
    @test health(f1) == 1
    @test health(use!(f1)) == 0
    @test health(restore!(f1)) == 0

    f2 = Consumable(bp)
    @test type_id(f1) == type_id(f2)
    @test id(f1) != id(f2)
    @test health(f2) == 1
    @test health(restore!(f2)) == 1
    @test health(use!(f2)) == 0

    f2 = Consumable(bp)
    @test health(decay!(f2)) == 1
    @test health(destroy!(f2)) == 0
end

@testset "Decayable" begin
    bp = DecayableBlueprint("D", 0.5)
    @test get_lifecycle(bp) == nothing
    @test get_maintenance_interval(bp) == INF

    @test bp.name == "D"
    @test bp.decay == 0.5

    decayable = Decayable(bp)
    @test health(decayable) == 1
    @test health(decay!(decayable)) == 0.5
    @test health(use!(decayable)) == 0.25
end

@testset "Product" begin
    oil_bp = ConsumableBlueprint("Oil")

    name = "Hammer"
    bp = ProductBlueprint(name, Restorable(wear = 0.1, restore = 0.1, maintenance_interval = 2, maintenance_res = Dict(oil_bp => 2), neglect_damage = 1))
    t1 = Product(bp)
    t2 = Product(bp)
    @test get_blueprint(t1).name == name
    @test get_name(t1) == name
    @test typeof(id(t1)) == Base.UUID
    @test typeof(type_id(t1)) == Base.UUID
    @test id(t1) != type_id(t1)
    @test type_id(t1) == type_id(t2)
    @test id(t1) != id(t2)
    @test health(t1) == 1
    @test health(use!(t1)) == 0.9
    @test health(restore!(t1)) == 1

    entities = Entities()
    push!(entities, Consumable(oil_bp))
    @test !maintenance_due(t1)
    @test maintenance_due(use!(t1))
    @test !maintain!(t1, entities)
    @test health(use!(t1)) == 0
    push!(entities, Consumable(oil_bp))
    @test maintain!(t1, entities)
    @test t1.used == 0
    @test isempty(entities)
end

@testset "Reconstructable" begin
    cb = ConsumableBlueprint("C")
    @test !reconstructable(cb)
    @test !reconstructable(Consumable(cb))

    pb = ProductBlueprint("P")
    @test !reconstructable(pb)
    @test !reconstructable(Product(pb))

    rec_pb = ProductBlueprint("Rec_P", Restorable(restore = 0.1, restoration_thresholds = [(0, 1)]))
    rec = Product(rec_pb)

    @test reconstructable(rec_pb)
    @test reconstructable(rec)
    @test health(damage!(rec, 1)) == 0
    @test health(restore!(rec)) == 0.1
end

@testset "Resourceless producer" begin
    cb = ConsumableBlueprint("Consumable")
    pb = ProducerBlueprint("Producer")
    pb.batch[cb] = 2

    p = Producer(pb)

    products = produce!(p, Entities())

    for product in products
        @test get_blueprint(product) == cb
    end
    @test length(products) == 2
end

@testset "Producer" begin
    labour_bp = ConsumableBlueprint("Labour")
    machine_bp = ProductBlueprint("Machine",
                    Restorable(restoration_thresholds = [(0, 0.1)], wear = 0.1))
    food_bp = ConsumableBlueprint("Food")

    @test !reconstructable(labour_bp)
    @test reconstructable(machine_bp)
    @test !reconstructable(food_bp)

    factory_bp = ProducerBlueprint(
        "Factory",
        batch_res = Dict(labour_bp => 2),
        batch_tools = Dict(machine_bp => 1),
        batch = Dict(food_bp => 1)
    )

    resources = Entities()
    push!(resources, [Consumable(labour_bp), Consumable(labour_bp), Product(machine_bp)])
    factory = Producer(factory_bp)

    products = produce!(factory, resources)

    @test !(labour_bp in keys(resources))
    @test machine_bp in keys(resources)

    @test health(collect(resources[machine_bp])[1]) == 0.9

    @test length(products) == 1

    for food in products
        @test get_name(food) == "Food"
        @test typeof(food) == Consumable
    end

    machine = collect(resources[machine_bp])[1]
    damage!(machine, 0.8)
    @test health(machine) == 0.1

    push!(resources, [Consumable(labour_bp), Consumable(labour_bp)])
    @test length(produce!(factory, resources)) == 1
    @test health(machine) == 0
    @test machine_bp in keys(resources)
end

@testset "Product health control" begin
    cb = ConsumableBlueprint("C")

    r = Restorable(
        damage_thresholds = [(1, 1), (0.8, 2)],
        restoration_thresholds = [(1, 2), (0.6, 1), (0.2, 0)],
        restore = 0.1,
        maintenance_interval = 10,
        maintenance_res = Dict([cb => 1]),
        neglect_damage = 0.5,
        wear = 0.1,
    )

    @test last(r.damage_thresholds) == (1, 1)

    pb = ProductBlueprint("P", r)
    product = Product(pb)

    @test !reconstructable(product)
    @test health(product) == 1
    @test health(damage!(product, 0.1)) == 0.9
    @test health(damage!(product, 0.2)) == 0.6
    @test health(use!(product)) == 0.4
    @test health(restore!(product)) == 0.5
    @test health(restore!(product)) == 0.6
    @test health(restore!(product)) == 0.8
    @test health(restore!(product)) == 1
    @test health(damage!(product, 0.3)) == 0.6
end

@testset "Entities" begin
    e = Entities()
    cb = ConsumableBlueprint("Consumable")
    pb = ProductBlueprint("Product", Restorable(wear = 0.1))
    c = Consumable(cb)
    p1 = Product(pb)
    p2 = Product(pb)

    @test num_entities(e, cb) == 0

    push!(e, c)
    push!(e, p1)
    push!(e, p2)
    @test length(e[cb]) == 1
    @test length(e[pb]) == 2
    use!(p1)

    h1_0 = false
    h0_9 = false
    for p in e[pb]
        h1_0 |= health(p) == 1
        h0_9 |= health(p) == 0.9
    end

    @test h1_0 && h0_9
end

@testset "extract!" begin
    e = Entities()
    cb = ConsumableBlueprint("Consumable")
    pb = ProductBlueprint("Product", Restorable(wear = 0.1))
    c = Consumable(cb)
    p1 = Product(pb)
    damage!(p1, 0.9)
    @test health(p1) == 0.1
    p2 = Product(pb)
    push!(e, c)
    push!(e, p1)
    push!(e, p2)
    req_res = Dict(cb => 1)
    req_tools = Dict(pb => 2)
    @test EconoSim.extract!(e, req_res, req_tools)
    @test length(keys(e)) == 1
    @test !(cb in keys(e))

    for product in e[pb]
        @test health(product) == 0.9
    end
end

@testset "Stock" begin
    bp = ConsumableBlueprint("C")
    stock = Stock()

    @test isempty(stock)
    @test min_stock(stock, bp) == 0
    @test max_stock(stock, bp) == 0

    min_stock!(stock, bp, 5)
    max_stock!(stock, bp, 10)

    @test isempty(stock)
    @test min_stock(stock, bp) == 5
    @test max_stock(stock, bp) == 10
    @test !stocked(stock, bp)
    @test !overstocked(stock, bp)

    add_stock!(stock, Consumable(bp))
    @test !isempty(stock)
    @test !stocked(stock, bp)
    @test !overstocked(stock, bp)
    @test current_stock(stock, bp) == 1

    products = retrieve_stock!(stock, bp, 2)

    @test length(products) == 1
    @test isempty(stock)
    @test !stocked(stock, bp)
    @test !overstocked(stock, bp)

    for i in 1:3
        products = [Consumable(bp), Consumable(bp)]
        add_stock!(stock, products)
    end

    @test isempty(products)

    @test !isempty(stock)
    @test stocked(stock, bp)
    @test !overstocked(stock, bp)
    @test current_stock(stock, bp) == 6

    stock_limits!(stock, bp, 1, 5)
    @test stocked(stock, bp)
    @test overstocked(stock, bp)
    @test current_stock(stock, bp) == 6

    products = retrieve_stock!(stock, bp, 3)
    @test length(products) == 3
    @test stocked(stock, bp)
    @test !overstocked(stock, bp)
    @test current_stock(stock, bp) == 3

    add_stock!(stock, products)
    @test length(products) == 1
    @test stocked(stock, bp)
    @test !overstocked(stock, bp)
    @test current_stock(stock, bp) == 5
end
