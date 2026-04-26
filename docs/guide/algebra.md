# Algebraic Operations

PathMap supports a complete **path algebra** — structural set operations
over tries that run in time proportional to the combined trie size, not
the number of individual keys.

---

## Whole-Map Operations

These return a new `PathMap`.  The originals are unmodified.

```julia
a = PathMap{Nothing}()
for k in [b"books:dune", b"books:foundation", b"movies:alien"]
    set_val_at!(a, k, nothing)
end

b = PathMap{Nothing}()
for k in [b"books:foundation", b"movies:alien", b"music:bowie"]
    set_val_at!(b, k, nothing)
end
```

### `pjoin` — Union

Paths present in **any** operand:

```julia
r = pjoin(a, b)
# books:dune, books:foundation, movies:alien, music:bowie
```

### `pmeet` — Intersection

Paths present in **all** operands:

```julia
r = pmeet(a, b)
# books:foundation, movies:alien
```

### `psubtract` — Difference

Paths in `a` that are **not** in `b`:

```julia
r = psubtract(a, b)
# books:dune
```

### `prestrict` — Prefix Restriction

Paths in `a` whose **prefix** exists in `b`:

```julia
prefixes = PathMap{Nothing}()
set_val_at!(prefixes, b"books:", nothing)

r = prestrict(a, prefixes)
# books:dune, books:foundation   (movies:alien excluded)
```

---

## In-Place Zipper Operations

Perform algebraic operations on a **subtrie** of an existing map,
in-place, via a write zipper.  This is more efficient when you only
need to modify part of a larger structure.

```julia
wz = write_zipper_at_path(m, b"catalog:")
src_rz = read_zipper(incoming_data)

wz_join_into!(wz, src_rz)         # union into subtrie at cursor
wz_meet_into!(wz, src_rz)         # intersect into subtrie at cursor
wz_subtract_into!(wz, src_rz)     # remove src paths from subtrie
wz_restrict!(wz, src_rz)          # restrict subtrie to src prefixes
```

---

## Drop-Head (Join K-Path)

Collapse `n` bytes from all paths, joining sub-tries as it proceeds.
Useful for removing a fixed-length key prefix from a set of paths.

```julia
# Trie: {books:dune, books:foundation, books:neuromancer}
wz = write_zipper(m)
wz_join_into_take!(wz, src_anr, true)  # consume src while joining

# Or at zipper level with k bytes dropped:
# (equivalent of insert_prefix! / remove_prefix! for lattice ops)
```

---

## Policy-Based Algebraic Operations

When values at coinciding paths need custom merge logic, use the
[Policy API](../advanced/policy_api.md):

```julia
# Instead of the default Lattice join:
pjoin_policy(a, b, SumPolicy())   # sum values at coinciding paths
pjoin_policy(a, b, MaxPolicy())   # max values
pjoin_policy(a, b, MergeWith((x, y) -> x ⊕ y))  # custom
```

---

## Algebraic Status Return Values

Zipper-level operations return an `AlgebraicStatus` indicating the
structural outcome:

| Value | Meaning |
|-------|---------|
| `ALG_STATUS_ELEMENT` | Result is a non-trivial new element |
| `ALG_STATUS_IDENTITY` | Self is unchanged (result = self) |
| `ALG_STATUS_NONE` | Result is empty (bottom of the lattice) |

---

## Complexity

All structural operations (join, meet, subtract, restrict) run in
**O(n + m)** time where n and m are the sizes of the two input tries.
This is optimal — no key-by-key comparison is needed.
