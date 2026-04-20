# ForgeCredoChecks

Custom [Credo](https://github.com/rrrene/credo) checks targeting `Enum`
anti-patterns LLMs commonly produce in Elixir code.

Stock Credo ships rules for `filter |> filter`, `reject |> reject`,
`map |> join`, etc. (same operation chained, or map terminating in a
collector). It does **not** catch chains where one operation composes
with the *complementary* one. These checks fill that gap.

## Rules

| Rule | Pattern flagged |
|---|---|
| `ForgeCredoChecks.FilterMap` | `Enum.filter \|> Enum.map` |
| `ForgeCredoChecks.RejectMap` | `Enum.reject \|> Enum.map` |
| `ForgeCredoChecks.MapReject` | `Enum.map \|> Enum.reject` |
| `ForgeCredoChecks.MapRejectNil` | `Enum.map \|> Enum.reject(&is_nil/1)` |

Each suggests `Enum.reduce/3` as the single-pass replacement. The
two-pass `filter |> map` style walks the input twice and allocates
an intermediate list; the reduce form does neither.

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
        {ForgeCredoChecks.MapRejectNil, []}
      ]
    }
  ]
}
```

## License

MIT
