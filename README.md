# ForgeCredoChecks

Custom [Credo](https://github.com/rrrene/credo) checks targeting `Enum`
anti-patterns LLMs (and some humans) commonly produce in Elixir code.

Stock Credo ships rules for `filter |> filter`, `reject |> reject`,
`map |> join`, etc. (same operation chained, or map terminating in a
collector). It does **not** catch chains where one operation composes
with the *complementary* one, or project-specific data-shape smells like
`Map.get/2 || fallback`. These checks fill that gap.

## Rules

### Two-pass Enum chains: use a comprehension

| Rule | Pattern flagged |
|---|---|
| `ForgeCredoChecks.FilterMap` | `Enum.filter \|> Enum.map` |
| `ForgeCredoChecks.RejectMap` | `Enum.reject \|> Enum.map` |
| `ForgeCredoChecks.MapReject` | `Enum.map \|> Enum.reject` |
| `ForgeCredoChecks.MapRejectNil` | `Enum.map \|> Enum.reject(&is_nil/1)` |

### Hand-rolled map building: use `Map.new/2`

| Rule | Pattern flagged |
|---|---|
| `ForgeCredoChecks.MapNewFromInto` | `Enum.into(%{}, fn ...)` |
| `ForgeCredoChecks.MapNewFromReduce` | `Enum.reduce(_, %{}, &Map.put(acc, k, v))` |

### Wasteful list-extremum patterns

| Rule | Pattern flagged | Replacement |
|---|---|---|
| `ForgeCredoChecks.ReverseListFirst` | `xs \|> Enum.reverse() \|> List.first()` | `List.last(xs)` |
| `ForgeCredoChecks.SortListFirst` | `Enum.sort \\| List.first` | `Enum.min`/`Enum.max`/`*_by` |

### `with`-macro conventions

| Rule | Pattern flagged | Configurable |
|---|---|---|
| `ForgeCredoChecks.WithBareBinding` | `=` clauses inside a `with` chain (must be `<-`) | no |
| `ForgeCredoChecks.WithElseClauses` | `with` blocks whose `else` exceeds `:max_clauses` | `:max_clauses` (default `1`) |
| `ForgeCredoChecks.WithResultTag` | `<-` clauses with atom-tagged LHS outside the allowlist | `:allowed_atoms` (default `[:ok, :error]`) |

### Map shape normalization

| Rule | Pattern flagged |
|---|---|
| `ForgeCredoChecks.MapGetWithOr` | `Map.get(_, _) || fallback` |
| `ForgeCredoChecks.ChainedMapGet` | `Map.get(_, _) || Map.get(_, _)` |

### LLM tells (function shape and idiomatic Elixir)

| Rule | Pattern flagged |
|---|---|
| `ForgeCredoChecks.InconsistentParamNames` | multi-clause function (within the same module) whose same positional argument has different base names across clauses. Clauses in separate `defimpl`/`defmodule` blocks are never cross-compared. |
| `ForgeCredoChecks.NoKernelShadowing` | variable binding (`=`, `fn`, `def`/`defp` param) named `max`/`min`/`length`/`elem`/`hd`/`tl`/`abs`/`round`/`trunc`/`div`/`rem`/`tuple_size`/`map_size`/`byte_size`/`bit_size` |
| `ForgeCredoChecks.NoUnnecessaryCatchAllRaise` | `def`/`defp` catch-all clause (every arg wildcard, body is `raise(...)`) when at least one sibling clause exists for the same `{name, arity}` in the same module. Single-clause raise functions (stubs, arity redirects) are not flagged. |
| `ForgeCredoChecks.NoCaseTrueFalse` | `case <bool_expr> do true -> ...; false -> ... end` (and `true`/`_`, `false`/`_` variants) |
| `ForgeCredoChecks.NoKernelOpInPipeline` | `pipeline \|> Kernel.<op>(arg)` for comparison/boolean operators (`==`/`!=`/`<`/`>`/`<=`/`>=`/`===`/`!==`/`and`/`or`) |
| `ForgeCredoChecks.NoInlineRegex` | inline `~r`/`~R` regex sigils inside function bodies; define regexes in module attributes instead |

### Official Elixir anti-patterns

A few of the [official Elixir anti-patterns](https://hexdocs.pm/elixir/what-anti-patterns.html)
that have a reliable AST signature. The rest of the catalog is either already
covered by stock Credo (e.g. `Warning.UnsafeToAtom`, `Refactor.FunctionArity`,
`Refactor.WithClauses`) or is too semantic to detect statically.

| Rule | Pattern flagged | Configurable |
|---|---|---|
| `ForgeCredoChecks.LargeStruct` | `defstruct` with `:max_fields` or more fields (a map of 32+ keys drops the BEAM flat-map representation) | `:max_fields` (default `32`) |
| `ForgeCredoChecks.UnsupervisedSpawn` | raw `spawn`/`spawn_link`/`spawn_monitor`/`Process.spawn` (start the process under a supervisor instead) | `:excluded_paths` |
| `ForgeCredoChecks.NamespaceTrespassing` | `defmodule` whose top segment is a dependency's namespace (`Phoenix.*`, `Ecto.*`, ...) | `:namespaces` |

### Architecture and test discipline

Boundary checks that enforce project structure rather than a language idiom.

| Rule | Pattern flagged | Configurable |
|---|---|---|
| `ForgeCredoChecks.PortProducerBoundary` | external-model producers (subprocess/HTTP dispatch) defined outside a declared boundary module | boundary allow-lists |
| `ForgeCredoChecks.NoSourceInspectionInTest` | tests that read or AST-parse `lib/*.ex` source (`File.read!` / `Code.string_to_quoted`, literal or carried as data) instead of exercising the real function | `:included_paths` |

The two-pass `Enum` chains walk the input twice and allocate intermediate
lists; a comprehension does both in one pass and preserves order naturally.
The map-building forms are pure equivalences with cleaner intent. The
sort-then-pick patterns are O(N log N) when O(N) suffices. The `with`
checks codify the convention that every clause uses `<-`, that step
return shapes get normalized in helpers (so non-matches fall through),
and that result tags stay within a project's intended vocabulary.

```elixir
# Flagged by FilterMap
things
|> Enum.filter(&keep?/1)
|> Enum.map(&transform/1)

# Preferred replacement: comprehension (one pass, in-order, no reverse)
for x <- things, keep?(x), do: transform(x)
```

For the `Enum`-chain checks the suggested fix order is:

1. **Comprehension** (preferred). Single pass, preserves order, no
   intermediate list, no `reverse` step.
2. **`Enum.flat_map/2`** when the transform is naturally 0-or-more (e.g.
   `parse(x)` returning `nil`-or-value).
3. **`Enum.reduce/3`** only as a last resort, and only when the consumer
   does not care about order. Do *not* tack on `|> Enum.reverse/1` to
   restore order: that second pass is exactly the tax the comprehension
   exists to avoid.

All Enum-chain rules detect the four AST shapes Elixir parses for any
two-call chain: direct nested call, two-step pipe, partial pipe + call,
and longer pipe chains.

## Installation

Add to `mix.exs`:

```elixir
def deps do
  [
    {:forge_credo_checks, "~> 0.7", only: [:dev, :test], runtime: false}
  ]
end
```

Then add to `.credo.exs`:

```elixir
%{
  configs: [
    %{
      name: "default",
      checks: [
        # ...
        {ForgeCredoChecks.FilterMap, []},
        {ForgeCredoChecks.RejectMap, []},
        {ForgeCredoChecks.MapReject, []},
        {ForgeCredoChecks.MapRejectNil, []},
        {ForgeCredoChecks.MapNewFromInto, []},
        {ForgeCredoChecks.MapNewFromReduce, []},
        {ForgeCredoChecks.ReverseListFirst, []},
        {ForgeCredoChecks.SortListFirst, []},
        {ForgeCredoChecks.WithBareBinding, []},
        {ForgeCredoChecks.WithElseClauses, []},
        {ForgeCredoChecks.WithResultTag, []},
        {ForgeCredoChecks.InconsistentParamNames, []},
        {ForgeCredoChecks.NoKernelShadowing, []},
        {ForgeCredoChecks.NoUnnecessaryCatchAllRaise, []},
        {ForgeCredoChecks.NoCaseTrueFalse, []},
        {ForgeCredoChecks.NoKernelOpInPipeline, []},
        {ForgeCredoChecks.NoInlineRegex, []},
        {ForgeCredoChecks.MapGetWithOr, []},
        {ForgeCredoChecks.ChainedMapGet, []},
        {ForgeCredoChecks.LargeStruct, []},
        {ForgeCredoChecks.UnsupervisedSpawn, []},
        {ForgeCredoChecks.NamespaceTrespassing, []}
      ]
    }
  ]
}
```

## License

MIT
