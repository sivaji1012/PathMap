using Test
using PathMap
const PM = PathMap.PathMap   # PathMap module and PathMap type share the same name

@testset "PathMap" begin

    @testset "basic CRUD" begin
        m = PM{Int}()
        set_val_at!(m, b"alpha", 1)
        set_val_at!(m, b"beta",  2)
        set_val_at!(m, b"gamma", 3)

        @test get_val_at(m, b"alpha") == 1
        @test get_val_at(m, b"beta")  == 2
        @test get_val_at(m, b"missing") === nothing
        @test path_exists_at(m, b"alpha")
        @test !path_exists_at(m, b"missing")
        @test val_count(m) == 3

        remove_val_at!(m, b"beta")
        @test get_val_at(m, b"beta") === nothing
        @test val_count(m) == 2
    end

    @testset "read zipper iteration" begin
        m = PM{Int}()
        for (k, v) in [("a", 1), ("b", 2), ("c", 3)]
            set_val_at!(m, Vector{UInt8}(k), v)
        end
        rz = read_zipper(m)
        count = 0
        while zipper_to_next_val!(rz)
            count += 1
        end
        @test count == 3
    end

    @testset "write zipper" begin
        m = PM{Int}()
        wz = write_zipper(m)
        wz_descend_to!(wz, b"prefix:key")
        wz_set_val!(wz, 42)
        @test get_val_at(m, b"prefix:key") == 42

        wz_remove_val!(wz)
        @test get_val_at(m, b"prefix:key") === nothing
    end

    @testset "algebraic ops (psubtract)" begin
        a = PM{Bool}()
        b = PM{Bool}()
        set_val_at!(a, b"x", true); set_val_at!(a, b"y", true)
        set_val_at!(b, b"y", true); set_val_at!(b, b"z", true)

        # Subtract: a - b = {x}
        result = deepcopy(a)
        wz = write_zipper(result)
        wz_subtract_into!(wz, ANRBorrowedRc(b.root))
        @test get_val_at(result, b"x") == true
        @test get_val_at(result, b"y") === nothing
        @test val_count(result) == 1
    end

    @testset "policy API" begin
        a = PM{Int}()
        b = PM{Int}()
        set_val_at!(a, b"x", 3); set_val_at!(a, b"y", 1)
        set_val_at!(b, b"x", 2); set_val_at!(b, b"z", 5)

        r = pjoin_policy(a, b, SumPolicy())
        @test get_val_at(r, b"x") == 5   # 3+2
        @test get_val_at(r, b"y") == 1   # only in a
        @test get_val_at(r, b"z") == 5   # only in b

        r2 = pjoin_policy(a, b, MaxPolicy())
        @test get_val_at(r2, b"x") == 3  # max(3,2)
    end

    @testset "morphisms" begin
        m = PM{Int}()
        for i in 1:5
            set_val_at!(m, Vector{UInt8}("k$i"), i)
        end
        total = cata_cached(m, (mask, children, val) ->
            (val !== nothing ? val : 0) + reduce(+, children, init=0))
        @test total == 15   # 1+2+3+4+5

        h = map_hash(m)
        @test h isa UInt64
        @test h != 0
    end

    @testset "insert_prefix / remove_prefix" begin
        m = PM{Int}()
        set_val_at!(m, b"foo:bar", 99)
        wz = write_zipper_at_path(m, b"foo:")
        @test wz_insert_prefix!(wz, b"ns:") == true
        @test get_val_at(m, b"ns:foo:bar") == 99
        @test get_val_at(m, b"foo:bar") === nothing
    end

    @testset "lazy COW — graft does not corrupt source" begin
        m1 = PM{Int}()
        set_val_at!(m1, b"hello", 42)

        m2 = PM{Int}()
        wz = write_zipper(m2)
        wz_descend_to!(wz, b"prefix:")
        wz_graft_map!(wz, m1)

        wz2 = write_zipper(m2)
        wz_descend_to!(wz2, b"prefix:hello")
        wz_set_val!(wz2, 99)

        @test get_val_at(m2, b"prefix:hello") == 99
        @test get_val_at(m1, b"hello")         == 42   # unchanged
    end

    @testset "serialization round-trip" begin
        m = PM{Bool}()
        set_val_at!(m, b"alpha", true)
        set_val_at!(m, b"beta",  true)
        io = IOBuffer()
        serialize_paths(m, io)
        seekstart(io)
        m2 = PM{Bool}()
        deserialize_paths(m2, io, true)
        @test val_count(m2) == val_count(m)
        @test path_exists_at(m2, b"alpha")
        @test path_exists_at(m2, b"beta")
    end

end
