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
# Load into memory (reads the whole file up-front)
act = act_open("data.act")

# Memory-mapped (lazy, zero-copy) — the OS faults pages on access
act = act_open_mmap("data.act")
```

`act_open_mmap` returns an `ArenaCompactTree` backed by an
`Mmap.mmap` view of the file (see
[src/pathmap/ArenaCompact.jl](../../src/pathmap/ArenaCompact.jl)
`act_open_mmap`).  Open is sub-millisecond regardless of file size;
RSS grows only with the pages a query actually touches.  Multiple
processes can share the same `.act` independently — the OS page cache
provides zero-copy fan-out.

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

## Load-Once / Mmap-Forever Workflow

For large, read-mostly datasets — knowledge graphs, connectomes,
embedding tables — the natural pattern is to do the expensive
text-parse + structural-share build **once**, snapshot to `.act`, then
cold-open the snapshot in every subsequent run:

```julia
function open_or_snapshot(text_input::AbstractString, act_path::AbstractString)
    if isfile(act_path)
        return act_open_mmap(act_path)        # fast path — every run after the first
    end
    # Slow path — runs exactly once
    m = build_pathmap_from(text_input)        # your bulk loader
    tree = act_from_zipper(m, _ -> UInt64(0)) # auxiliary payload per val (UInt64 here)
    act_save(tree, act_path)
    m = nothing; GC.gc()                      # drop the in-RAM copy
    act_open_mmap(act_path)                   # re-open via mmap
end
```

Because the zipper API is polymorphic over the backend (see
[guide/zippers.md](zippers.md) — "Trie-Format Polymorphism"), every
query function written against the in-RAM `PathMap` works unchanged on
the mmap'd trie.  The dataset moves from "needs ~minutes + GBs of RAM
to load" to "0.25 ms to open, ~0 RAM" on the second run, without any
change in the consuming code.

### Measured example — 3.73 M-edge real-world dataset

FAFB v783 *Drosophila* connectome, encoded as 4-arity s-expressions
in MORK (`(syn pre post cnt)`) and saved via `act_from_zipper` +
`act_save`:

| Stage | Time | RSS |
|-------|------|-----|
| First-run text parse + bulk load | ~125 s | 4.7 GB |
| Snapshot to `.act` | ~36 s | 4.7 GB |
| `.act` on disk | — | **41.7 MB** (113× smaller than RAM) |
| `act_open_mmap` (cold, every later run) | **0.25 ms** | ~0 |
| Per-query read (zipper algebra) | µs-scale | grows lazily |

Worked end-to-end driver:
[`packages/Core/examples/connectome/info_flow_all_modalities.jl`](../../../Core/examples/connectome/info_flow_all_modalities.jl) —
opens the mmap'd `.act` in 0.25 ms and runs reach-flow over all 7
afferent modalities in ~14 s total.

---

## Path Counting and Statistics

```julia
counters = PathMapCounters(m)

counters.val_count       # number of values
counters.node_count      # total nodes
counters.shared_count    # nodes referenced more than once
counters.depth           # maximum trie depth
```
