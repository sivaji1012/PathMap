# Contributing to PathMap.jl

## Development Setup

```julia
using Pkg
Pkg.develop(path = ".")
Pkg.test("PathMap")
```

## Running Tests

```bash
# Warm REPL (recommended — no JIT overhead on second run)
julia --project=. -i test/runtests.jl

# Cold start verification
julia --project=. -e 'using Pkg; Pkg.test("PathMap")'
```

## Running Benchmarks

```bash
julia --project=. benchmarks/benchmarks.jl
julia --project=. benchmarks/benchmarks.jl --tune   # full calibration
```

## Running Examples

```bash
julia --project=. examples/word_index.jl
julia --project=. examples/trie_algebra.jl
```

## Registering a New Release

PathMap.jl uses [Registrator.jl](https://github.com/JuliaRegistries/Registrator.jl)
for Julia General Registry releases.

1. Update `version` in `Project.toml`
2. Commit and push to `main`
3. Comment `@JuliaRegistrator register` on the commit on GitHub
4. Registrator opens a PR to [JuliaRegistries/General](https://github.com/JuliaRegistries/General)
5. After merge (usually within 15 min), `Pkg.add("PathMap")` will work

## Package Info

| Field | Value |
|-------|-------|
| Name | `PathMap` |
| UUID | `a8b3d4e5-f012-4567-89ab-cdef01234567` |
| Repo | `https://github.com/sivaji1012/PathMap.git` |
| Min Julia | `1.10` |
