using Test
using EconoSim
using Intervals

@testset "Thresholds" begin
    threshold_up = convert_thresholds([(0, 1)], EconoSim.up)
    @test length(threshold_up) == 1
    @test isclosed(threshold_up[1][1])
    @test first(threshold_up[1][1]) == 0
    @test last(threshold_up[1][1]) == 1

    threshold_down = convert_thresholds([(1, 1)], EconoSim.down)
    @test length(threshold_down) == 1
    @test isclosed(threshold_down[1][1])
    @test first(threshold_down[1][1]) == 0
    @test last(threshold_down[1][1]) == 1

    thresholds_up = convert_thresholds([(0.5, 1), (1, 0.5)], up)
    @test length(thresholds_up) == 2
    @test EconoSim.is_left_closed(thresholds_up[1][1])
    @test EconoSim.is_right_open(thresholds_up[1][1])
    @test first(thresholds_up[1][1]) == 0
    @test last(thresholds_up[1][1]) == 0.5
    @test thresholds_up[1][2] == 1
    @test EconoSim.is_left_closed(thresholds_up[2][1])
    @test EconoSim.is_right_closed(thresholds_up[2][1])
    @test first(thresholds_up[2][1]) == 0.5
    @test last(thresholds_up[2][1]) == 1
    @test thresholds_up[2][2] == 0.5

    thresholds_down = convert_thresholds([(0.5, 1), (1, 0.5)], down)
    @test EconoSim.is_left_open(thresholds_down[1][1])
    @test EconoSim.is_right_closed(thresholds_down[1][1])
    @test first(thresholds_down[1][1]) == 0.5
    @test last(thresholds_down[1][1]) == 1
    @test thresholds_down[1][2] == 0.5
    @test EconoSim.is_left_closed(thresholds_down[2][1])
    @test EconoSim.is_right_closed(thresholds_down[2][1])
    @test first(thresholds_down[2][1]) == 0
    @test last(thresholds_down[2][1]) == 0.5
    @test thresholds_down[2][2] == 1
end

@testset "Restorable" begin
    bp = ConsumableBlueprint("C")

    r = Restorable()
    @test r.damage_thresholds == convert_thresholds([(1, 1.0)], down)
    @test r.restoration_thresholds == convert_thresholds([(0, 1.0)], up)
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
    @test r.damage_thresholds == convert_thresholds([(1, 1), (0.8, 2)], down)
    @test r.restoration_thresholds == convert_thresholds([(1, 2), (0.6, 1), (0.2, 0)], up)
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
    use!(f1)
    @test health(f1) == 0
    restore!(f1)
    @test health(f1) == 0

    f2 = Consumable(bp)
    @test type_id(f1) == type_id(f2)
    @test id(f1) != id(f2)
    @test health(f2) == 1
    restore!(f2)
    @test health(f2) == 1
    use!(f2)
    @test health(f2) == 0

    f2 = Consumable(bp)
    decay!(f2)
    @test health(f2) == 1
    destroy!(f2)
    @test health(f2) == 0
end

@testset "Decayable" begin
    bp = DecayableBlueprint("D", 0.5)
    @test get_lifecycle(bp) == nothing
    @test get_maintenance_interval(bp) == INF

    @test bp.name == "D"
    @test bp.decay == 0.5

    decayable = Decayable(bp)
    @test health(decayable) == 1
    decay!(decayable)
    @test health(decayable) == 0.5
    use!(decayable)
    @test health(decayable) == 0.25
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
    use!(t1)
    @test health(t1) == 0.9
    restore!(t1)
    @test health(t1) == 1

    entities = Entities()
    push!(entities, Consumable(oil_bp))
    push!(entities, Consumable(oil_bp))
    @test !maintenance_due(t1)
    use!(t1)
    @test maintenance_due(t1)
    @test maintain!(t1, entities)[1]
    @test isempty(entities)
    use!(t1)
    use!(t1)
    use!(t1)
    @test restorable(t1)
    @test health(t1) == 0
    push!(entities, Consumable(oil_bp))
    push!(entities, Consumable(oil_bp))
    @test maintain!(t1, entities)[1]
    @test t1.uses == 0
    @test isempty(entities)
end

@testset "Reconstructable" begin
    cb = ConsumableBlueprint("C")
    @test !restorable(cb)
    @test !restorable(Consumable(cb))

    pb = ProductBlueprint("P")
    @test !restorable(pb)
    @test !restorable(Product(pb))

    rec_pb = ProductBlueprint("Rec_P", Restorable(restore = 0.1, restoration_thresholds = [(0, 1)]))
    rec = Product(rec_pb)

    @test restorable(rec_pb)
    @test restorable(rec)
    damage!(rec, 1)
    @test health(rec) == 0
    restore!(rec)
    @test health(rec) == 0.1
end

@testset "Resourceless producer" begin
    cb = ConsumableBlueprint("Consumable")
    pb = ProducerBlueprint("Producer")
    pb.batch[cb] = 2

    p = Producer(pb)

    products = produce!(p, Entities())
    counter = 0

    for set in collect(values(products))
        for product in set
            @test get_blueprint(product) == cb
            counter += 1
        end
    end

    @test counter == 2
end

@testset "Producer" begin
    labour_bp = ConsumableBlueprint("Labour")
    machine_bp = ProductBlueprint("Machine",
                    Restorable(restoration_thresholds = [(0, 0.1)], restore = 0.1, wear = 0.1))
    food_bp = ConsumableBlueprint("Food")

    @test !restorable(labour_bp)
    @test restorable(machine_bp)
    @test !restorable(food_bp)

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

    @test num_entities(products) == 1
    @test num_entities(products, food_bp) == 1

    for food in products[food_bp]
        @test get_name(food) == "Food"
        @test typeof(food) == Consumable
    end

    machine = collect(resources[machine_bp])[1]
    damage!(machine, 0.8)
    @test health(machine) == 0.1

    push!(resources, [Consumable(labour_bp), Consumable(labour_bp)])
    @test num_entities(produce!(factory, resources)) == 1
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

    @test first(r.damage_thresholds)[1] == RightInterval(0.8, 1)
    @test first(r.damage_thresholds)[2] == 1
    @test last(r.damage_thresholds)[1] == ClosedInterval(0, 0.8)
    @test last(r.damage_thresholds)[2] == 2

    @test first(r.restoration_thresholds)[1] == LeftInterval(0, 0.2)
    @test first(r.restoration_thresholds)[2] == 0
    @test r.restoration_thresholds[2][1] == LeftInterval(0.2, 0.6)
    @test r.restoration_thresholds[2][2] == 1
    @test last(r.restoration_thresholds)[1] == ClosedInterval(0.6, 1)
    @test last(r.restoration_thresholds)[2] == 2

    pb = ProductBlueprint("P", r)
    product = Product(pb)

    @test restorable(product)
    @test health(product) == 1
    damage!(product, 0.1)
    @test health(product) == 0.9
    damage!(product, 0.2)
    @test health(product) == 0.6
    use!(product)
    @test health(product) == 0.4
    restore!(product)
    @test health(product) == 0.5
    restore!(product)
    @test health(product) == 0.6
    restore!(product)
    @test health(product) == 0.8
    restore!(product)
    @test health(product) == 1
    damage!(product, 0.3)
    @test health(product) == 0.6
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
    @test num_entities(e) == 3
    @test num_entities(e, cb) == 1
    @test length(e[cb]) == 1
    @test num_entities(e, pb) == 2
    @test length(e[pb]) == 2
    use!(p1)

    h1_0 = false
    h0_9 = false

    for p in e[pb]
        h1_0 |= health(p) == 1
        h0_9 |= health(p) == 0.9
    end

    @test h1_0 && h0_9

    e2 = Entities()
    push!(e2, Consumable(cb))
    push!(e2, Consumable(cb))

    merge!(e, e2)
    @test num_entities(e) == 5
    @test num_entities(e, cb) == 3
    @test num_entities(e, pb) == 2
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
    result = EconoSim.extract!(e, req_res, req_tools)
    @test result[1]
    @test length(keys(e)) == 1
    @test !(cb in keys(e))
    @test num_entities(e) == 1
    @test num_entities(e, pb) == 1

    for product in e[pb]
        @test health(product) == 0.9
    end
end

@testset "waste" begin
    w_bp = ConsumableBlueprint("Waste")
    wp_bp = ProductBlueprint("Waste product")
    res_bp = ConsumableBlueprint("Resource", Dict([w_bp => 1, wp_bp => 2]))

    res = Consumable(res_bp)
    e = destroy!(res)
    @test num_entities(e) == 3
    @test num_entities(e, w_bp) == 1
    @test num_entities(e, wp_bp) == 2

    tw_bp = ConsumableBlueprint("Tool waste")
    tool_bp = ConsumableBlueprint("One use tool", Dict(tw_bp => 1))
    p_bp = ConsumableBlueprint("Product")

    prod_bp = ProducerBlueprint("Producer", Restorable(),
            batch_res = Dict([res_bp => 1]),
            batch_tools = Dict([tool_bp => 1]),
            batch = Dict([p_bp => 2]),
            waste = Dict([w_bp => 1]))

    producer = Producer(prod_bp)
    e = Entities()
    push!(e, Consumable(res_bp))
    push!(e, Consumable(tool_bp))
    production = produce!(producer, e)

    @test num_entities(e) == 0
    @test num_entities(production) == 6
    @test num_entities(production, w_bp) == 1
    @test num_entities(production, wp_bp) == 2
    @test num_entities(production, tw_bp) == 1
    @test num_entities(production, p_bp) == 2

    w = destroy!(producer)
    @test num_entities(w) == 1
    @test num_entities(w, w_bp) == 1
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

    e = Entities()

    for i in 1:6
        push!(e, Consumable(bp))
    end

    add_stock!(stock, e, force = true)
    @test isempty(e)
    @test stocked(stock, bp)
    @test overstocked(stock, bp)
    @test current_stock(stock, bp) == 11
end
