# Policy API — Custom Value-Merge at Call Time

The Policy API decouples the value-merge behaviour of `pjoin` and
related operations from the Julia type system.

By default, PathMap uses the `Lattice` trait: the merge behaviour for
values at coinciding paths is fixed per value type `V`.  This prevents
using different strategies (e.g., `min` vs `max` vs `sum`) for the same
type in different contexts.

The Policy API solves this by accepting a **merge policy** at call time.

---

## Policy Contract

A policy is any callable with the signature:

```julia
policy(v_self::V, v_src::V) -> Union{Nothing, V}
```

- Return `nothing` → drop both values at this path (meet-None semantics)
- Return a value  → keep that value (element semantics)

---

## Built-in Policies

| Constructor | Behaviour |
|-------------|-----------|
| `TakeFirst()` | Keep `v_self`, ignore `v_src` |
| `TakeLast()` | Overwrite with `v_src` |
| `MergeWith(f)` | Apply `f(v_self, v_src)` |
| `SumPolicy()` | `v_self + v_src` |
| `ProdPolicy()` | `v_self * v_src` |
| `MinPolicy()` | `min(v_self, v_src)` |
| `MaxPolicy()` | `max(v_self, v_src)` |

---

## Usage

### Whole-map join with a policy

```julia
counts_a = PathMap{Float64}()
set_val_at!(counts_a, b"red",  3.0)
set_val_at!(counts_a, b"blue", 1.0)

counts_b = PathMap{Float64}()
set_val_at!(counts_b, b"blue", 4.0)
set_val_at!(counts_b, b"green", 2.0)

result = pjoin_policy(counts_a, counts_b, SumPolicy())
get_val_at(result, b"red")    # 3.0   (only in a)
get_val_at(result, b"blue")   # 5.0   (1.0 + 4.0)
get_val_at(result, b"green")  # 2.0   (only in b)
```

### In-place zipper variant

```julia
wz = write_zipper(accumulator)
wz_join_policy!(wz, incoming_map, MaxPolicy())
```

### Custom policy

```julia
# Merge: keep value only if both agree (equality gate)
agree_policy = (a, b) -> a == b ? a : nothing

result = pjoin_policy(a, b, agree_policy)
```

---

## Motivation — MORK Sink Semantics

MORK's float-reduction sinks (`fmin`, `fmax`, `fsum`, `fprod`) all
operate on `Float64` values but want different merge strategies:

```metta
(exec (1)
    (, (n $x))
    (O
        (fmin (min $c) $c $x)    ;; update accumulator with min
        (fmax (max $c) $c $x)    ;; update accumulator with max
        (fsum (sum $c) $c $x)    ;; accumulate sum
        (fprod (prod $c) $c $x)  ;; accumulate product
    )
)
```

With the Policy API, each sink can now express its merge behaviour
as a first-class value rather than requiring a separate value type.

---

## Design Notes

The structural trie operations (which paths exist in the result) are
unchanged — the Policy API only affects what happens **at value positions**
where both maps have a value.

Paths present in only one map are copied as-is, regardless of policy.

The implementation uses a synchronised DFS walk over a `WriteZipperCore`
(self) and a `ReadZipperCore` (src) — no changes to the node layer are
required.
