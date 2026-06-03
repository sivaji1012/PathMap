# API Reference

Complete index of exported symbols from `PathMap.jl`.

---

## PathMap — Core Container

| Symbol | Kind | Description |
|--------|------|-------------|
| `PathMap{V}` | Type | Byte-keyed trie map with values of type `V` |
| `PathMap{V,A}` | Type | With explicit allocator (advanced) |
| `get_val_at(m, path)` | Function | Lookup — returns `V` or `nothing` |
| `set_val_at!(m, path, val)` | Function | Insert or overwrite |
| `remove_val_at!(m, path)` | Function | Delete (optionally pruning) |
| `path_exists_at(m, path)` | Function | True if any path extends `path` |
| `val_count(m)` | Function | Total number of stored values |
| `pjoin(a, b)` | Function | Structural union (new map) |
| `pmeet(a, b)` | Function | Structural intersection (new map) |
| `psubtract(a, b)` | Function | Structural difference (new map) |
| `prestrict(a, b)` | Function | Restrict by prefix (new map) |
| `pjoin_policy(a, b, policy)` | Function | Policy-based join |

---

## Read Zipper

| Symbol | Kind | Description |
|--------|------|-------------|
| `ReadZipperCore{V,A}` | Type | Read-only cursor |
| `read_zipper(m)` | Function | Create zipper at root |
| `read_zipper_at_path(m, path)` | Function | Create zipper at path |
| `zipper_val(z)` | Function | Value at cursor |
| `zipper_is_val(z)` | Function | True if value exists |
| `zipper_path_exists(z)` | Function | True if subtrie is non-empty |
| `zipper_path(z)` | Function | Current path from origin |
| `zipper_child_mask(z)` | Function | `ByteMask` of child bytes |
| `zipper_child_count(z)` | Function | Number of children |
| `zipper_val_count(z)` | Function | Values in subtrie |
| `zipper_descend_to!(z, k)` | Function | Descend to sub-path `k` |
| `zipper_descend_to_byte!(z, b)` | Function | Descend one byte |
| `zipper_ascend!(z, n)` | Function | Ascend `n` bytes |
| `zipper_ascend_byte!(z)` | Function | Ascend one byte |
| `zipper_reset!(z)` | Function | Return to origin |
| `zipper_to_next_val!(z)` | Function | Advance to next value (DFS) |
| `zipper_to_next_step!(z)` | Function | Advance one step |
| `zipper_to_next_sibling_byte!(z)` | Function | Next sibling |
| `zipper_descend_until!(z)` | Function | Descend to next branch/value |
| `tr_fork_read_zipper(z)` | Function | Clone zipper at current position |
| `trie_ref_at_path(z, path)` | Function | Borrowed reference to subtrie |

---

## Write Zipper

| Symbol | Kind | Description |
|--------|------|-------------|
| `WriteZipperCore{V,A}` | Type | Mutable cursor |
| `write_zipper(m)` | Function | Create write zipper at root |
| `write_zipper_at_path(m, path)` | Function | Create write zipper at path |
| `wz_set_val!(z, val)` | Function | Set value at cursor |
| `wz_remove_val!(z)` | Function | Remove value at cursor |
| `wz_get_val(z)` | Function | Read value at cursor |
| `wz_is_val(z)` | Function | True if value exists at cursor |
| `wz_get_or_set_val!(z, default)` | Function | Upsert |
| `wz_path_exists(z)` | Function | True if subtrie non-empty |
| `wz_path(z)` | Function | Current path from origin |
| `wz_child_mask(z)` | Function | Child bytes at cursor |
| `wz_descend_to!(z, k)` | Function | Extend path and descend |
| `wz_descend_to_byte!(z, b)` | Function | Descend one byte |
| `wz_ascend!(z, n)` | Function | Ascend `n` bytes |
| `wz_ascend_byte!(z)` | Function | Ascend one byte |
| `wz_reset!(z)` | Function | Return to origin |
| `wz_at_root(z)` | Function | True if at origin |
| `wz_create_path!(z)` | Function | Create valueless path |
| `wz_prune_path!(z)` | Function | Remove empty dangling paths |
| `wz_graft!(z, src)` | Function | Replace subtrie at cursor |
| `wz_graft_map!(z, m)` | Function | Replace subtrie with map `m` |
| `wz_take_map!(z)` | Function | Remove and return subtrie |
| `wz_take_focus!(z)` | Function | Remove and return focus node |
| `wz_insert_prefix!(z, prefix)` | Function | Prepend bytes to all paths |
| `wz_remove_prefix!(z, n)` | Function | Strip `n` bytes from all paths |
| `wz_join_into!(z, src)` | Function | Join `src` into cursor subtrie |
| `wz_join_map_into!(z, m)` | Function | Join map into cursor subtrie |
| `wz_join_into_take!(z, src)` | Function | Join consuming `src` |
| `wz_meet_into!(z, src)` | Function | Meet `src` into cursor subtrie |
| `wz_subtract_into!(z, src)` | Function | Subtract `src` from subtrie |
| `wz_restrict!(z, src)` | Function | Restrict subtrie to `src` |
| `wz_remove_branches!(z)` | Function | Remove all branches |
| `wz_remove_unmasked_branches!(z, mask)` | Function | Remove unmasked branches |
| `wz_join_policy!(z, src, policy)` | Function | Policy-based join in-place |

---

## Abstract Zippers

| Symbol | Kind | Description |
|--------|------|-------------|
| `PrefixZipper` | Type | Read zipper with prepended prefix |
| `pz_*` functions | — | PrefixZipper operations |
| `OverlayZipper` | Type | Fused view of two zippers |
| `oz_*` functions | — | OverlayZipper operations |
| `ProductZipper` | Type | Two-factor Cartesian product |
| `ProductZipperG` | Type | N-factor generic product |
| `DependentZipper` | Type | Factor-guided navigation |
| `EmptyZipper` | Type | Virtual infinite empty trie |

---

## ZipperHead

| Symbol | Kind | Description |
|--------|------|-------------|
| `ZipperHead` | Type | Multi-zipper coordinator |
| `ZipperHeadOwned` | Type | Thread-safe variant |
| `zh_read_zipper_at_path(zh, p)` | Function | Read zipper with conflict check |
| `zh_write_zipper_at_exclusive_path(zh, p)` | Function | Exclusive write zipper |
| `zh_cleanup_write_zipper!(zh, wz)` | Function | Release exclusive access |

---

## Morphisms

| Symbol | Kind | Description |
|--------|------|-------------|
| `cata_side_effect(m, f)` | Function | Stepping fold with path |
| `cata_jumping_side_effect(m, f)` | Function | Jumping fold with path |
| `cata_cached(m, f)` | Function | Cached stepping fold |
| `cata_jumping_cached(m, f)` | Function | Cached jumping fold |
| `cata_hybrid_cached(m, f)` | Function | Cached fold with path (A.0005) |
| `cata_jumping_hybrid_cached(m, f)` | Function | Cached jumping fold with path |
| `ana_jumping!(m, f)` | Function | Anamorphism (trie unfold) |
| `map_hash(m)` | Function | Structural hash using sharing |
| `TrieBuilder` | Type | Incremental trie construction |

---

## Policy API

| Symbol | Kind | Description |
|--------|------|-------------|
| `TakeFirst()` | Function | Policy: keep self value |
| `TakeLast()` | Function | Policy: overwrite with src value |
| `MergeWith(f)` | Function | Policy: apply custom `f` |
| `SumPolicy()` | Function | Policy: `+` |
| `ProdPolicy()` | Function | Policy: `*` |
| `MinPolicy()` | Function | Policy: `min` |
| `MaxPolicy()` | Function | Policy: `max` |
| `pjoin_policy(a, b, p)` | Function | Policy-based whole-map join |
| `wz_join_policy!(z, src, p)` | Function | Policy-based in-place join |

---

## Serialization

| Symbol | Kind | Description |
|--------|------|-------------|
| `serialize_paths(m)` | Function | Encode to `.paths` format |
| `deserialize_paths(V, buf)` | Function | Decode from `.paths` format |
| `serialize_paths_with_auxdata(m, f)` | Function | With per-path auxiliary data |
| `deserialize_paths_with_auxdata(buf, f)` | Function | Decode with aux data |
| `for_each_deserialized_path(buf, f)` | Function | Streaming decode |
| `ArenaCompactTree` | Type | Read-only compact trie |
| `ACTZipper` | Type | Cursor for `ArenaCompactTree` |
| `act_open(path)` | Function | Open `.act` file |
| `act_open_mmap(path)` | Function | Memory-mapped open |

---

## Utilities

| Symbol | Kind | Description |
|--------|------|-------------|
| `ByteMask` | Type | 256-bit byte-presence mask |
| `ByteMaskIter` | Type | Iterator over set bytes |
| `iter(m::ByteMask)` | Function | Create iterator |
| `next_bit(m, b)` | Function | Next set bit after `b` |
| `prev_bit(m, b)` | Function | Previous set bit before `b` |
| `PathMapCounters` | Type | Profiling counters |
| `Allocator` | Type | Abstract allocator |
| `GlobalAlloc` | Type | Default (heap) allocator |
