"""
PolicyOps — Policy-based algebraic operations on PathMap (A.0003).

The existing pjoin/pmeet/psubtract operations use the `Lattice` trait on
the value type `V` to decide how two values at the same path are merged.
This couples merge behavior to the type, making it impossible to use
different strategies for the same `V` in different contexts.

This module decouples value-merge behavior into a **policy** supplied at
call time. The structural trie-level operations (which paths survive) are
unchanged; only the value-merge at coinciding paths is customisable.

Design (A.0003):
  - A policy is any callable `(v_self::V, v_src::V) -> Union{Nothing, V}`
    * `nothing` → drop both values at this path (meet-None semantics)
    * a value  → keep that value (element semantics)
  - Built-in policy constructors: TakeFirst, TakeLast, MergeWith,
    SumPolicy, ProdPolicy, MinPolicy, MaxPolicy.
  - Public API:
    * `wz_join_policy!(wz, src_map, policy)` — in-place zipper-level join
    * `pjoin_policy(m1, m2, policy)` — whole-map join returning new PathMap

Implementation: synchronised DFS over a WriteZipper (self) and a
ReadZipper (src).  At every coinciding value position the policy is
applied; structural branches present only in src are inserted as-is.
"""

# =====================================================================
# Built-in policy constructors
# =====================================================================

"""
    TakeFirst() -> Function

Policy: keep the self value, ignore src.  Equivalent to identity join.
"""
TakeFirst() = (v_self, _v_src) -> v_self

"""
    TakeLast() -> Function

Policy: keep the src value, overwrite self.
"""
TakeLast() = (_v_self, v_src) -> v_src

"""
    MergeWith(f) -> Function

Policy: apply `f(v_self, v_src)` and keep the result.
`f` must return a value of type `V` (never nothing).
"""
MergeWith(f) = (v_self, v_src) -> f(v_self, v_src)

"""
    SumPolicy() -> Function

Policy: `v_self + v_src`.  Requires `+` defined on `V`.
"""
SumPolicy()  = MergeWith(+)

"""
    ProdPolicy() -> Function

Policy: `v_self * v_src`.  Requires `*` defined on `V`.
"""
ProdPolicy() = MergeWith(*)

"""
    MinPolicy() -> Function

Policy: `min(v_self, v_src)`.  Requires `<` defined on `V`.
"""
MinPolicy()  = MergeWith(min)

"""
    MaxPolicy() -> Function

Policy: `max(v_self, v_src)`.  Requires `>` defined on `V`.
"""
MaxPolicy()  = MergeWith(max)

# =====================================================================
# _policy_join_recursive! — synchronised DFS core
# =====================================================================
#
# Simultaneously walks `wz` (write zipper into self) and `rz` (read
# zipper over src) byte-by-byte.  At each position:
#   - Both have value  → apply policy
#   - Only src has val → insert into self
#   - Only self has val → keep unchanged
#   - src has children → recurse into each

function _policy_join_recursive!(wz::WriteZipperCore{V,A},
                                  rz::ReadZipperCore{V,A},
                                  policy::F) where {V, A, F}
    # --- value merge at current cursor position ---
    w_val = wz_get_val(wz)
    r_val = zipper_val(rz)

    if w_val !== nothing && r_val !== nothing
        merged = policy(w_val, r_val)
        if merged === nothing
            wz_remove_val!(wz, false)
        else
            wz_set_val!(wz, merged)
        end
    elseif r_val !== nothing
        wz_set_val!(wz, r_val)
    end
    # (only self has value → no-op, keep as-is)

    # --- recurse into every child byte present in src ---
    r_mask = zipper_child_mask(rz)
    isempty(r_mask) && return

    for byte in iter(r_mask)
        zipper_descend_to_byte!(rz, byte)
        wz_descend_to_byte!(wz, byte)
        _policy_join_recursive!(wz, rz, policy)
        wz_ascend_byte!(wz)
        zipper_ascend_byte!(rz)
    end
end

# =====================================================================
# wz_join_policy! — in-place zipper-level join with policy
# =====================================================================

"""
    wz_join_policy!(wz, src_map, policy) -> nothing

Join `src_map` into the subtrie at `wz`'s cursor position, using
`policy(v_self, v_src)` to merge values at coinciding paths instead of
the `Lattice` trait.

`policy` must be callable as `(v_self::V, v_src::V) -> Union{Nothing, V}`.

Example — sum all values at coinciding paths:
```julia
wz_join_policy!(wz, other, SumPolicy())
```
"""
function wz_join_policy!(wz::WriteZipperCore{V,A},
                          src::PathMap{V,A},
                          policy) where {V,A}
    src.root === nothing && return nothing
    rz = read_zipper(src)
    _policy_join_recursive!(wz, rz, policy)
    nothing
end

# =====================================================================
# pjoin_policy — whole-map join returning a new PathMap
# =====================================================================

"""
    pjoin_policy(m1, m2, policy) -> PathMap

Return a new `PathMap` that is the join of `m1` and `m2`, using
`policy(v1, v2)` to merge values at paths present in both maps.

Paths present in only one map are copied as-is (structural join).

Example — max over coinciding float values:
```julia
result = pjoin_policy(counts_a, counts_b, MaxPolicy())
```
"""
function pjoin_policy(m1::PathMap{V,A}, m2::PathMap{V,A}, policy) where {V,A}
    result = deepcopy(m1)
    m2.root === nothing && return result
    wz = write_zipper(result)
    rz = read_zipper(m2)
    _policy_join_recursive!(wz, rz, policy)
    result
end

# =====================================================================
# Exports
# =====================================================================

export TakeFirst, TakeLast, MergeWith
export SumPolicy, ProdPolicy, MinPolicy, MaxPolicy
export wz_join_policy!, pjoin_policy
