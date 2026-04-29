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
        # Cursor at "foo:" — insert_prefix prepends "ns:" within that subtrie
        # "bar" → 99 becomes "ns:bar" → 99, full path: "foo:ns:bar"
        wz = write_zipper_at_path(m, b"foo:")
        @test wz_insert_prefix!(wz, b"ns:") == true
        @test get_val_at(m, b"foo:ns:bar") == 99
        @test get_val_at(m, b"foo:bar") === nothing

        # insert_prefix at root prepends to all absolute paths
        m2 = PM{Int}()
        set_val_at!(m2, b"eagle", 1)
        set_val_at!(m2, b"penguin", 2)
        wz2 = write_zipper(m2)
        @test wz_insert_prefix!(wz2, b"bird:") == true
        @test get_val_at(m2, b"bird:eagle")   == 1
        @test get_val_at(m2, b"bird:penguin") == 2
        @test get_val_at(m2, b"eagle") === nothing
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

    @testset "ArenaCompact mmap round-trip" begin
        m = PM{UInt64}()
        set_val_at!(m, b"hello",       UInt64(42))
        set_val_at!(m, b"world",       UInt64(99))
        set_val_at!(m, b"hello_world", UInt64(7))

        tree_vec = act_from_zipper(m, v -> v)
        tmpfile  = tempname() * ".act"
        act_save(tree_vec, tmpfile)

        # act_open_mmap: mmap-backed, zero-copy read
        tree_mmap = act_open_mmap(tmpfile)
        @test tree_mmap isa ArenaCompactTree
        @test length(tree_mmap.data) == filesize(tmpfile)
        @test tree_mmap.data[1:8] == ACT_MAGIC

        # value round-trip via mmap
        @test act_get_val_at(tree_mmap, b"hello")       === UInt64(42)
        @test act_get_val_at(tree_mmap, b"world")       === UInt64(99)
        @test act_get_val_at(tree_mmap, b"hello_world") === UInt64(7)
        @test act_get_val_at(tree_mmap, b"missing")     === nothing

        # mmap and copy results must agree on every key
        tree_copy = act_open(tmpfile)
        for key in (b"hello", b"world", b"hello_world", b"missing")
            @test act_get_val_at(tree_mmap, key) === act_get_val_at(tree_copy, key)
        end

        # ACTZipper traversal over mmap-backed tree
        z = act_read_zipper(tree_mmap)
        @test act_val_count(z) == 3

        rm(tmpfile; force=true)
    end

    @testset "remove_val_at! with prune" begin
        m = PM{Int}()
        set_val_at!(m, b"abc", 1)
        set_val_at!(m, b"abd", 2)
        set_val_at!(m, b"xyz", 3)

        old = remove_val_at!(m, b"abc", true)
        @test old === 1
        @test get_val_at(m, b"abc") === nothing
        @test get_val_at(m, b"abd") === 2
        @test get_val_at(m, b"xyz") === 3
    end

    @testset "wz_remove_branches! with prune" begin
        m = PM{Int}()
        set_val_at!(m, b"foo:a", 10)
        set_val_at!(m, b"foo:b", 20)
        set_val_at!(m, b"bar",   30)

        wz = write_zipper_at_path(m, b"foo:")
        wz_remove_branches!(wz, true)

        @test get_val_at(m, b"foo:a") === nothing
        @test get_val_at(m, b"foo:b") === nothing
        @test get_val_at(m, b"bar")   === 30
    end

end
