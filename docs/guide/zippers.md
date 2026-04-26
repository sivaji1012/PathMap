# Zipper Guide

A **zipper** is a cursor into a `PathMap` trie.  It maintains a current
position ("focus") and provides efficient navigation and mutation without
scanning the entire structure.

---

## Read Zipper

A `ReadZipperCore` provides read-only access.  Multiple read zippers
can coexist safely.

### Creating

```julia
rz  = read_zipper(m)                    # start at map root
rz2 = read_zipper_at_path(m, b"users:") # start at a sub-path
```

### Navigating

```julia
# Descend
zipper_descend_to!(rz, b"alice:score")  # absolute sub-path from origin
zipper_descend_to_byte!(rz, UInt8('a')) # one byte

# Ascend
zipper_ascend!(rz, 6)                   # 6 bytes up
zipper_ascend_byte!(rz)                 # one byte up

# Jump to branch/value (skipping monotone paths)
zipper_descend_until!(rz)               # descend to next branch or value
zipper_ascend_until!(rz)                # ascend to next branch
zipper_ascend_until_branch!(rz)         # ascend to next 2+-child branch

# Reset
zipper_reset!(rz)                       # return to origin
```

### Querying at the Focus

```julia
zipper_val(rz)            # V or nothing
zipper_is_val(rz)         # true if value exists
zipper_path_exists(rz)    # true if any path exists below
zipper_path(rz)           # current path bytes from origin
zipper_child_mask(rz)     # ByteMask of existing child bytes
zipper_child_count(rz)    # number of children
zipper_val_count(rz)      # values in the entire subtrie
```

### Iterating

```julia
# Visit every value in DFS order
rz = read_zipper_at_path(m, b"users:")
while zipper_to_next_val!(rz)
    path = String(zipper_path(rz))
    val  = zipper_val(rz)
    println("$path => $val")
end

# Visit every node (including internal nodes)
rz = read_zipper(m)
while zipper_to_next_step!(rz)
    # at each node...
end

# K-path iteration (paths of exactly k bytes)
zipper_descend_first_k_path!(rz, 4)     # first 4-byte path
while zipper_to_next_k_path!(rz, 4)     # next 4-byte path
    # ...
end
```

### Sibling Navigation

```julia
# Within a node, move between sibling bytes
zipper_to_next_sibling_byte!(rz)    # next sibling
zipper_to_prev_sibling_byte!(rz)    # previous sibling
```

### Forking

Clone a zipper at its current position — useful for parallel traversal:

```julia
rz2 = tr_fork_read_zipper(rz)      # independent copy at same position
```

### Subtrie References

Borrow a reference to the subtrie at the current focus without copying:

```julia
ref = trie_ref_at_path(rz, b"subtrie:")   # TrieRef (borrowed)
# use ref for read-only operations, then drop
```

---

## Write Zipper

A `WriteZipperCore` provides mutable access to a `PathMap`.

### Creating

```julia
wz = write_zipper(m)                    # at root
wz = write_zipper_at_path(m, b"users:") # at a sub-path
```

### Reading at the Focus

```julia
wz_get_val(wz)         # V or nothing
wz_is_val(wz)          # true if value exists
wz_path_exists(wz)     # true if any path exists below
wz_path(wz)            # current path bytes from origin
wz_at_root(wz)         # true if at origin
wz_child_mask(wz)      # ByteMask of child bytes
wz_child_count(wz)     # number of children
```

### Mutating Values

```julia
wz_set_val!(wz, 42)          # create or overwrite value
wz_remove_val!(wz)           # remove value (keep paths)
wz_remove_val!(wz, true)     # remove value, prune empty paths
wz_get_or_set_val!(wz, 0)    # return existing or set default
```

### Structural Operations

```julia
wz_create_path!(wz)          # create valueless dangling path
wz_prune_path!(wz)           # remove empty dangling paths
wz_remove_branches!(wz)      # remove all branches at cursor
wz_remove_branches!(wz, true) # and prune dangling paths
wz_remove_unmasked_branches!(wz, mask)  # keep only masked branches
```

### Grafting and Taking

```julia
wz_graft!(wz, src_anr)         # replace subtrie with src
wz_graft_map!(wz, m2)          # replace subtrie with map m2
subtrie = wz_take_focus!(wz)   # remove and return focus node
m3 = wz_take_map!(wz)          # remove and return as PathMap
```

### Path Prefix Manipulation

```julia
# Prepend "prefix:" to every path in the subtrie at cursor
wz_insert_prefix!(wz, b"prefix:")

# Strip 7 bytes of prefix from all paths in subtrie at cursor
wz_remove_prefix!(wz, 7)
```

**Example** — namespace remapping:

```julia
m = PathMap{Int}()
set_val_at!(m, b"bob:score", 95)
set_val_at!(m, b"bob:rank",  1)

wz = write_zipper_at_path(m, b"bob:")
wz_insert_prefix!(wz, b"users:")

# m now has: users:bob:score => 95, users:bob:rank => 1
```

### Algebraic Operations at Cursor

```julia
rz = read_zipper(other)
wz_join_into!(wz, rz)          # union src into cursor subtrie
wz_meet_into!(wz, rz)          # intersect src into cursor subtrie
wz_subtract_into!(wz, rz)      # remove src paths from cursor subtrie
wz_restrict!(wz, rz)           # restrict cursor subtrie to src prefixes
wz_join_map_into!(wz, m2)      # join from a PathMap directly
wz_join_into_take!(wz, rz)     # join consuming src
wz_join_policy!(wz, m2, SumPolicy())  # policy-based join
```

### Resetting

```julia
wz_reset!(wz)     # return to origin
```

---

## Abstract Zippers

Abstract zippers compose read-only views without materialising data.

### PrefixZipper — Virtual Path Prefix

Reads from a base zipper as if all paths had a fixed prefix prepended:

```julia
rz = read_zipper_at_path(m, b"data:")
pz = PrefixZipper(b"ns:", rz)

# pz sees paths as "ns:data:..." instead of "data:..."
zipper_descend_to!(pz, b"ns:data:key")
```

### OverlayZipper — Fused View

Reads from two zippers simultaneously, presenting their union:

```julia
oz = OverlayZipper(rz_a, rz_b)
# Navigation respects both underlying zippers
```

### ProductZipper — Cartesian Product

Presents the Cartesian product of two (or N, with `ProductZipperG`)
zippers' path sets:

```julia
# Two-factor product
pz = ProductZipper(rz_a, rz_b)

# N-factor product
pzg = ProductZipperG([rz_a, rz_b, rz_c])
```

### DependentZipper — Factor-Guided Navigation

Navigates a "result" zipper guided by the current position of a
"factor" zipper:

```julia
dz = DependentZipper(factor_rz, result_rz)
```

### EmptyZipper — Virtual Empty Trie

An always-empty read zipper, useful as a neutral element in compositions:

```julia
ez = EmptyZipper{Int, GlobalAlloc}()
```

---

## ZipperHead — Safe Multi-Zipper Access

`ZipperHead` coordinates multiple zippers on the same `PathMap`,
enforcing non-overlapping exclusive access for write zippers:

```julia
zh = ZipperHead(m)

# Multiple read zippers anywhere
rz1 = zh_read_zipper_at_path(zh, b"section:a:")
rz2 = zh_read_zipper_at_path(zh, b"section:b:")

# Exclusive write zipper — panics if path overlaps existing writers
wz  = zh_write_zipper_at_exclusive_path(zh, b"section:c:")

# When done, release the exclusive lock
zh_cleanup_write_zipper!(zh, wz)
```

`ZipperHeadOwned` is the `Send + Sync` variant for multi-threaded use:

```julia
zho = ZipperHeadOwned(m)
```

---

## Absolute Path Information

When navigating with abstract zippers or across multiple levels:

```julia
zipper_origin_path(rz)         # absolute path of the zipper's root
pz_root_prefix_path(pz)        # prefix path from absolute root
pz_prefix_path_below_focus(pz) # prefix bytes below the current focus
```

---

## Performance Tips

- Prefer `zipper_descend_until!` / `cata_jumping_*` over stepping
  byte-by-byte through monotone paths — jumping skips O(n) node visits.
- `tr_fork_read_zipper` is cheap (O(1)) — fork freely for parallel
  sub-traversals.
- `ZipperHead` enables concurrent read + exclusive write without locks
  when path ranges are known to be disjoint.
- `write_zipper_at_path` is equivalent to `write_zipper` +
  `wz_descend_to!` but avoids an extra allocation.
