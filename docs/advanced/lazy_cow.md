# Lazy Copy-on-Write WriteZipper

PathMap.jl implements the **lazy copy-on-write** design described in
[A.0004 of the PathMap book](https://trueagi-io.github.io/PathMap/A.0004_scouting_write_zipper.html),
a capability not yet present in the upstream Rust release.

---

## The Problem

PathMap uses structural sharing: multiple `PathMap` instances can point to
the same underlying trie nodes.  When you `graft_map` or `pjoin` two maps,
the result shares nodes with its sources.

```julia
m1 = PathMap{Int}()
set_val_at!(m1, b"hello", 42)

m2 = PathMap{Int}()
wz = write_zipper(m2)
wz_descend_to!(wz, b"prefix:")
wz_graft_map!(wz, m1)     # m2 now SHARES m1's subtrie
```

Without copy-on-write protection, writing through `m2`'s write zipper
would silently mutate `m1`'s subtrie.

---

## The Solution — Two-Phase COW

PathMap.jl implements COW in two distinct phases:

### Phase 1: Lazy Descent (no cloning)

`_wz_descend_to_internal!` traverses the trie read-only, pushing node
references onto the focus stack **without cloning**.  This is the "scouting"
phase — we traverse as if reading.

### Phase 2: Uniquify at First Write

Before any mutation (`set_val!`, `remove_val!`, `graft`, algebraic ops),
`_wz_ensure_write_unique!` walks the focus stack from root to focus:

1. **Explicitly shared** (`refcount > 1`): calls `make_unique!` in-place.
   Since `copy()` was called when sharing was established, the refcount
   correctly reflects sharing.

2. **Transitively shared** (`refcount == 1` but parent was just cloned):
   creates a fresh `TrieNodeODRc` via `clone_self`, replaces the focus stack
   entry, and re-links the parent to the new node.
   This handles children that are reachable from the original (pre-clone)
   ancestor's subtrie even though no explicit `copy()` was called on them.

3. **Re-linking**: when a parent is cloned via `clone_self` (which uses
   `deepcopy`), its child slots hold stale deepcopies rather than the live
   focus stack entries.  The uniquify pass replaces those stale slots.

---

## Sharing Semantics

Sharing is established explicitly when grafting:

```julia
# wz_graft_map! calls copy(map.root) before planting —
# bumps refcount so sharing is tracked
wz_graft_map!(wz, source_map)
```

After this, `source_map.root` and the grafted subtrie share the same
`_refcount` `Ref`.  Any subsequent write through the write zipper will
detect `refcount > 1` and clone before mutating.

---

## Correctness Guarantee

```julia
m1 = PathMap{Int}()
set_val_at!(m1, b"hello", 42)

m2 = PathMap{Int}()
wz2 = write_zipper(m2)
wz_descend_to!(wz2, b"prefix:")
wz_graft_map!(wz2, m1)

# Write through m2 — m1 is NOT mutated
wz3 = write_zipper(m2)
wz_descend_to!(wz3, b"prefix:hello")
wz_set_val!(wz3, 99)

get_val_at(m2, b"prefix:hello")  # 99
get_val_at(m1, b"hello")         # 42  ← unchanged
```

---

## Implementation Notes

- `TrieNodeODRc` carries an explicit `Base.RefValue{Int}` refcount
  (mirroring `Arc::strong_count` semantics).
- `copy(rc)` bumps the shared `Ref` and creates a new `TrieNodeODRc`
  pointing to the same inner `AbstractTrieNode` (like `Arc::clone`).
- `make_unique!(rc)` clones the inner node if `refcount > 1` (like
  `Arc::make_mut`).
- The "transitively shared" case is unique to Julia's design and has
  no direct Rust equivalent — it arises because Julia's GC replaces
  Rust's borrow checker, so implicit aliasing through parent nodes
  must be detected and resolved at write time.
