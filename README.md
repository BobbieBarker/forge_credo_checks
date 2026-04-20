# ForgeCredoChecks

Custom [Credo](https://github.com/rrrene/credo) checks targeting `Enum`
anti-patterns LLMs commonly produce in Elixir code.

Stock Credo ships rules for `filter |> filter`, `reject |> reject`,
`map |> join`, etc. (same operation chained, or map terminating in a
collector). It does **not** catch chains where one operation composes
with the *complementary* one. These checks fill that gap.

## Rules

### Two-pass Enum chains → `Enum.reduce/3`

| Rule | Pattern flagged |
|---|---|
| `ForgeCredoChecks.FilterMap` | `Enum.filter \|> Enum.map` |
| `ForgeCredoChecks.RejectMap` | `Enum.reject \|> Enum.map` |
| `ForgeCredoChecks.MapReject` | `Enum.map \|> Enum.reject` |
| `ForgeCredoChecks.MapRejectNil` | `Enum.map \|> Enum.reject(&is_nil/1)` |

### Hand-rolled map building → `Map.new/2`

| Rule | Pattern flagged |
|---|---|
| `ForgeCredoChecks.MapNewFromInto` | `Enum.into(%{}, fn ...)` |
| `ForgeCredoChecks.MapNewFromReduce` | `Enum.reduce(_, %{}, &Map.put(acc, k, v))` |

### Wasteful list-extremum patterns

| Rule | Pattern flagged | Replacement |
|---|---|---|
| `ForgeCredoChecks.ReverseListFirst` | `xs \|> Enum.reverse() \|> List.first()` | `List.last(xs)` |
| `ForgeCredoChecks.SortListFirst` | `Enum.sort \\| List.first` | `Enum.min`/`Enum.max`/`*_by` |

The two-pass chains walk the input twice and allocate intermediate lists;
`Enum.reduce/3` does neither. The map-building forms are pure equivalences
with cleaner intent. The sort-then-pick patterns are O(N log N) when
O(N) suffices.

```elixir
# Flagged by FilterMap
things
|> Enum.filter(&keep?/1)
|> Enum.map(&transform/1)

# Suggested replacement
Enum.reduce(things, [], fn x, acc ->
  if keep?(x), do: [transform(x) | acc], else: acc
end)
```

Append `|> Enum.reverse()` only if the output order matters. For
most callers (set membership, `Map.new`, sort, sum, count, etc.) it
does not.

All four rules detect the four AST shapes Elixir parses for any
two-call chain: direct nested call, two-step pipe, partial pipe +
call, and longer pipe chains.

## Installation

Not yet published to hex. Install via git for now:

```elixir
def deps do
  [
    {:forge_credo_checks,
     github: "BobbieBarker/forge_credo_checks", only: [:dev, :test], runtime: false}
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
        {ForgeCredoChecks.SortListFirst, []}
      ]
    }
  ]
}
```

## License

MIT
