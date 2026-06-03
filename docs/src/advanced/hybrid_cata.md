# Hybrid Cached Catamorphism

PathMap.jl implements the **hybrid cached catamorphism** proposed in
[A.0005 of the PathMap book](https://trueagi-io.github.io/PathMap/A.0005_cached_cata_and_path_visibility.html).
This design is not yet implemented in the upstream Rust release.

---

## The Problem

The two existing catamorphism modes have a fundamental trade-off:

| Mode | Caches? | Path visible? |
|------|---------|--------------|
| `cata_side_effect` | ✗ | ✓ |
| `cata_cached` | ✓ | ✗ |

**Why `cata_cached` cannot pass paths:**
If the fold result `W` incorporates path information, then the same
trie node at two different paths would produce different `W` values —
making the cache incorrect.

---

## The Solution — `used_bytes` Discriminator

The hybrid cached catamorphism resolves this by asking the closure
to declare **how many trailing path bytes it used** to construct `W`.

```julia
alg_f(mask, children, val, sub_path, full_path) -> (W, used_bytes::Int)
```

The cache key is then:

- `used_bytes == 0`: key = `node_id` only.
  Same caching behaviour as `cata_cached` — the result is path-independent.

- `used_bytes == n`: key = `(node_id, path[end-n:end])`.
  The cached entry is only reused when the last `n` bytes of the current
  path match those stored when the entry was created.

This makes it safe to incorporate path information into `W` while still
benefiting from structural sharing where the result is path-independent.

---

## API

```julia
# Stepping (visits every fork)
cata_hybrid_cached(m, alg_f)

# Jumping (skips monotone path segments)
cata_jumping_hybrid_cached(m, alg_f)
```

Both accept zipper variants directly:
```julia
cata_hybrid_cached(rz::ReadZipperCore, alg_f)
```

---

## Examples

### Path-independent (used_bytes = 0)

Identical to `cata_cached` — full cache sharing, path ignored:

```julia
depth = cata_hybrid_cached(m, (mask, ch, val, sub, path) ->
    (1 + reduce(max, ch, init=0), 0))
```

### Path-qualified (used_bytes = 1)

Result depends on the last byte of the path — cache entries are
specific to that byte:

```julia
# Tag each value with its path's final byte
tagged = cata_hybrid_cached(m, (mask, ch, val, sub, path) -> begin
    w = val !== nothing ? (path[end], val) : nothing
    (w, 1)    # used_bytes = 1: last byte matters
end)
```

### MORKL use case (Adam's original motivation)

In the MORKL interpreter, programs are represented as variable-free tries
where absolute paths encode variable references.  The hybrid cata enables
folding such a trie while:
- Caching subtrie results that are shared across multiple call sites
- Retaining full path visibility for resolving variable references

```julia
result = cata_hybrid_cached(program_trie,
    (mask, children, val, sub_path, full_path) -> begin
        # full_path gives us the absolute position in the program
        # used_bytes tells how much of that position matters for caching
        interpret_node(mask, children, val, full_path)
    end)
```

---

## Implementation

The cache is a `Dict{UInt64, Tuple{Any, Vector{UInt8}}}` mapping
`node_id → (W, path_suffix)`.

**On cache store:** after computing `(W, used)`, store:
```
cache[node_id] = (W, path[end-used+1:end])
```
(empty suffix when `used == 0`).

**On cache lookup:** retrieve the stored entry and validate:
```
cached_suffix == current_path[end-n+1:end]
```
If they match, the cached `W` is returned.  On a suffix mismatch, the
subtrie is refolded and the cache entry is overwritten.

This validation is O(n) per lookup where n = `used_bytes`, which is
typically very small (often 0 or 1).
