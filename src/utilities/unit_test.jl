using Test
using .EconoSim

@testset "Percentage" begin
    @test_throws MethodError Percentage()
    @test Percentage(0).value == 0.0
    @test Percentage(1).value == 1.0
    @test Percentage(0.5).value == 0.5
    @test Percentage(-1).value == 0.0
    @test Percentage(2).value == 1.0

    @test Percentage(0.1) + Percentage(0.2) == Percentage(0.3)
    @test Percentage(0.1) + 0.2 == Percentage(0.3)
    @test 0.2 + Percentage(0.1) == Percentage(0.3)

    @test 1 - Percentage(0.8) == Percentage(0.2)
    @test Percentage(1) - 0.8 == Percentage(0.2)
    @test 1 - Percentage(0.8) == 0.2
    @test Percentage(1) - 0.8 == 0.2

    @test Percentage(0.1) + Percentage(0.2) == 0.3
    @test Percentage(0.1) + 0.2 == 0.3
    @test 0.2 + Percentage(0.1) == 0.3

    @test 0.1 < Percentage(0.2)
    @test Percentage(0.2) < 0.3
end

@testset "Health" begin
    @test Health() == Health(1)
    @test Health(0).current == 0.0
    @test Health(1).current == 1.0
    @test Health(0.5).current == 0.5
    @test Health(-1).current == 0.0
    @test Health(2).current == 1.0

    @test Health(0.1) + Health(0.2) == Health(0.3)
    @test Health(0.1) + 0.2 == Health(0.3)
    @test 0.2 + Health(0.1) == Health(0.3)

    @test 1 - Health(0.8) == Health(0.2)
    @test Health(1) - 0.8 == Health(0.2)
    @test 1 - Health(0.8) == 0.2
    @test Health(1) - 0.8 == 0.2

    @test Health(0.1) + Health(0.2) == 0.3
    @test Health(0.1) + 0.2 == 0.3
    @test 0.2 + Health(0.1) == 0.3

    @test 0.1 < Health(0.2)
    @test Health(0.2) < 0.3

    @test Health(1) > Percentage(0.9)

    @test Health(0.1) + Percentage(0.2) == 0.3
end

@testset "Mixed" begin
    p = Percentage(0.1)
    h = Health(0.2)

    @test p + h == h + p == 0.3
    @test h - p == 0.1
    @test p - h == 0
    @test h * p == p * h == 0.02
    @test p / h == 0.5
    @test h / p == 1
end

@testset "Delete element" begin
    a = [1, 2, 3]
    @test delete_element!(a, 2) == [1, 3]
end
