# Serialization

PathMap.jl supports two serialization formats for persisting tries to
disk and loading them back efficiently.

---

## `.paths` Format

The `.paths` format stores each (path, value) pair as a length-prefixed
byte sequence, with the whole buffer zlib-compressed.  It is the general-
purpose format for any `PathMap{V}`.

### Basic Round-Trip

```julia
m = PathMap{Int}()
set_val_at!(m, b"alpha", 1)
set_val_at!(m, b"beta",  2)
set_val_at!(m, b"gamma", 3)

# Serialize — returns a Vector{UInt8}
buf = serialize_paths(m)

# Deserialize — pass the value type
m2 = deserialize_paths(Int, buf)
get_val_at(m2, b"alpha")   # 1
```

### With Auxiliary Data

When values cannot be encoded as raw bytes (arbitrary Julia objects),
supply encoder and decoder functions:

```julia
# Encode: (path, value) → Vector{UInt8}
# Decode: Vector{UInt8} → value

buf = serialize_paths_with_auxdata(m,
    (path, val) -> reinterpret(UInt8, [val]))

m3 = deserialize_paths_with_auxdata(buf,
    bytes -> reinterpret(Int, bytes)[1])
```

### Streaming Decode

Process paths one by one without loading the full trie into memory:

```julia
for_each_deserialized_path(buf) do path, aux_bytes
    println(String(path), " → ", aux_bytes)
end
```

### From Functions

Build `.paths` output directly from iterator-style callbacks:

```julia
buf = serialize_paths_from_funcs(
    (emit) -> begin
        emit(b"key1", nothing)
        emit(b"key2", nothing)
    end)
```

---

## ACT — ArenaCompact Format

The **ArenaCompact Trie** (ACT) format stores the trie in a compact,
cache-friendly binary representation suitable for memory-mapped,
zero-copy read access.  It is ideal for large, read-heavy datasets.

### Writing

```julia
# Build a PathMap, then serialise to ACT
write_act(m, "data.act")
```

### Reading

```julia
# Load into memory
act = act_open("data.act")

# Memory-mapped (zero-copy) — does not load into RAM
act = act_open_mmap("data.act")
```

### Navigating with ACTZipper

```julia
az = ACTZipper(act)

# Same navigation API as ReadZipperCore
zipper_descend_to!(az, b"users:")
zipper_val(az)
zipper_child_mask(az)

while zipper_to_next_val!(az)
    path = String(zipper_path(az))
    val  = zipper_val(az)
    println("$path => $val")
end
```

### When to Use Each Format

| Criterion | `.paths` | ACT |
|-----------|---------|-----|
| Arbitrary value types | ✓ | Limited |
| Structural sharing preserved | Partial | ✓ |
| Memory-mapped access | ✗ | ✓ |
| Mutable after load | ✓ (rebuild) | ✗ (read-only) |
| Best for | General exchange | Large read-heavy datasets |

---

## Path Counting and Statistics

```julia
counters = PathMapCounters(m)

counters.val_count       # number of values
counters.node_count      # total nodes
counters.shared_count    # nodes referenced more than once
counters.depth           # maximum trie depth
```
