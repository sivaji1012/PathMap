# Morphisms — Fold and Unfold

PathMap.jl provides first-class **catamorphisms** (folds from leaves to
root) and **anamorphisms** (unfolds from a seed) over the trie structure.

Morphisms exploit **structural sharing**: a subtrie shared across multiple
locations is processed once, and the result is reused — giving the cached
variants sub-linear time complexity on tries with significant sharing.

---

## Catamorphism — Folding a Trie

A catamorphism visits every fork in the trie from leaves up to the root,
calling your closure at each fork to combine child results.

### Closure Signatures

| Variant | Signature |
|---------|-----------|
| `cata_side_effect` | `(mask, children, val, path) → W` |
| `cata_jumping_side_effect` | `(mask, children, jump_len, val, path) → W` |
| `cata_cached` | `(mask, children, val) → W` |
| `cata_jumping_cached` | `(mask, children, val, sub_path) → W` |
| `cata_hybrid_cached` | `(mask, children, val, sub_path, path) → (W, used_bytes)` |

**Arguments:**
- `mask::ByteMask` — which child bytes exist at this fork
- `children::Vector{W}` — fold results from each child (in byte order)
- `val::Union{Nothing, V}` — value at this fork (if any)
- `path::Vector{UInt8}` — absolute path to this fork (side-effect variants)
- `jump_len::Int` — bytes jumped over to reach this fork (jumping variants)
- `sub_path::Vector{UInt8}` — the jumped sub-path (jumping cached variants)

### Choosing a Variant

| Need | Use |
|------|-----|
| Full path in closure | `cata_side_effect` or `cata_hybrid_cached` |
| Maximum performance, no path needed | `cata_cached` |
| Sparse tries (long paths, few branches) | any `*_jumping_*` variant |
| Both caching and path visibility | `cata_hybrid_cached` |

---

## Examples

### Count all values

```julia
count = cata_cached(m, (mask, children, val) ->
    (val !== nothing ? 1 : 0) + reduce(+, children, init=0))
```

### Collect paths with values

```julia
paths = String[]
cata_side_effect(m, (mask, children, val, path) -> begin
    val !== nothing && push!(paths, String(copy(path)))
    nothing
end)
```

### Hash a trie structurally

```julia
h = map_hash(m)    # built-in, exploits sharing
```

### Compute trie depth

```julia
depth = cata_cached(m, (mask, children, val) ->
    1 + reduce(max, children, init=0))
```

### Aggregate with path context (hybrid cata)

```julia
# Sum values, weighted by the last byte of their path
weighted_sum = cata_hybrid_cached(m,
    (mask, children, val, sub, path) -> begin
        w = if val !== nothing
            val * Int(path[end])
        else
            reduce(+, children, init=0)
        end
        # used_bytes=1: cache is specific to last path byte
        (w, 1)
    end)
```

### Build an index (side-effect cata)

```julia
index = Dict{Int, Vector{String}}()    # value → [path, ...]
cata_side_effect(m, (mask, children, val, path) -> begin
    if val !== nothing
        push!(get!(index, val, String[]), String(copy(path)))
    end
    nothing
end)
```

---

## Jumping Variants

The **jumping** variants skip over monotone path segments (stretches with
only one child and no value).  They call `alg_f` only at true branch
points, with `jump_len` indicating how many bytes were skipped:

```julia
# Non-jumping: alg_f called at every node
# Jumping: alg_f called only at forks and values

cata_jumping_cached(m,
    (mask, children, val, sub_path) -> begin
        # sub_path is the jumped segment that led here
        length(sub_path)   # bytes in the compressed edge
    end)
```

Jumping is dramatically faster for sparse tries (e.g. a trie of 1000
10-character keys has ~9000 monotone steps — jumping reduces alg_f calls
from ~9000 to ~1000).

---

## Cached Variants

Cached variants use **structural sharing** to memoise results by node
identity:

```julia
# If two paths share a subtrie node, that node's fold is computed once
shared = PathMap{Int}()
set_val_at!(shared, b"x", 1)

m = PathMap{Int}()
wz = write_zipper(m)
wz_descend_to!(wz, b"left:"); wz_graft_map!(wz, shared)
wz_descend_to!(wz, b"right:"); wz_graft_map!(wz, shared)

# cata_cached folds the shared subtrie once, reuses for both "left:" and "right:"
total = cata_cached(m, (mask, children, val) ->
    (val !== nothing ? val : 0) + reduce(+, children, init=0))
# result: 2 (correct), but fold computed only once for the shared node
```

**Hybrid cached** (`cata_hybrid_cached`) additionally supports path
visibility — see [Hybrid Cached Cata](../advanced/hybrid_cata.md).

---

## Anamorphism — Building a Trie

`ana_jumping!` builds a trie from a seed by calling a generator function
at each step:

```julia
m = PathMap{Int}()
ana_jumping!(m, state -> begin
    # return (byte, child_state, value) tuples to build paths
    # return [] or nothing to terminate
    ...
end)
```

### TrieBuilder — Incremental Construction

For performance-critical construction from sorted byte sequences:

```julia
tb = TrieBuilder{Int, GlobalAlloc}(GlobalAlloc())

tb_push!(tb, b"alpha")
tb_push!(tb, b"beta")
tb_push!(tb, b"gamma")

m = PathMap(tb)    # materialise the trie
```

`TrieBuilder` assumes keys are pushed in **sorted (lexicographic) order**.
Random-order insertion uses `set_val_at!` instead.

---

## ReadZipperCore Overloads

All cata functions accept a `ReadZipperCore` directly, allowing
morphisms over a **subtrie** without wrapping it in a new `PathMap`:

```julia
rz = read_zipper_at_path(m, b"subtree:")
count = cata_cached(rz, (mask, children, val) ->
    (val !== nothing ? 1 : 0) + reduce(+, children, init=0))
```

---

## Complexity

| Variant | Time | Space |
|---------|------|-------|
| `cata_side_effect` | O(n) | O(depth) |
| `cata_cached` | O(unique_nodes) | O(unique_nodes) |
| `cata_hybrid_cached` | O(unique × suffix_len) | O(unique_nodes) |

Where `n` = total node count, `unique_nodes` = number of structurally
distinct nodes (≤ n, often << n on tries with sharing).
