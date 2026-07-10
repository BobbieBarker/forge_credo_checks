---
type: adr
id: 12
title: Compose with Pipes, Not Named Intermediates
status: accepted
date: 2026-05-08
tags: [elixir, style, pipes, composition, captures]
description: "Express sequential transformations through |> pipes, not chained rebindings of one name. Use & captures over anonymous wrappers. Use then/2 to adapt return shapes when the next call doesn't accept the threaded value first. Use tap/2 for in-chain side effects."
---
# ADR-012: Compose with Pipes, Not Named Intermediates

Compose. Do not rebind. Use the pipe-first idiom and the small set of helpers (`then/2`, `tap/2`) that handle the cases where pipe-first does not directly fit.

## Context

- `|>` is a compile-time macro: `lhs |> f(args)` expands to `f(lhs, args)`. The runtime is identical to a sequential rebinding; the choice is about source legibility.
- Pipelines make data flow vertical and visible. Rebinding one name across multiple lines (`x = step_one(x); x = step_two(x); ...`) makes data flow horizontal and permits the smuggling of unrelated statements between bindings, which a pipeline forbids by construction.
- Captures (`&Mod.fun/N`, `&Mod.fun(&1, args)`) directly express "call this function with these arguments." Anonymous-function wrappers around a single call introduce a binding that has no role beyond passing through.
- `then/2` and `tap/2` cover the cases where pipe-first does not fit: shape adapters and in-chain side effects.

## Consequence

- Functions read top-to-bottom as transformation pipelines. Sequential rebindings of the same name are a refactor signal.
- Anonymous-function wrappers around single calls are replaced with captures.
- `then/2` and `tap/2` are reached for routinely. Side effects in pipelines are visible: a reader sees `tap/2` and knows the threaded value is preserved.

## Rules

- Express sequential transformations as pipelines, not chained variable bindings. Three rebindings of `x` (or `data`, `state`) is the canonical smell.
- Use `&` captures instead of anonymous wrappers for thin wrappers around a single call. `Enum.map(items, &String.upcase/1)`, not `Enum.map(items, fn item -> String.upcase(item) end)`.
- The carve-out for captures: when the lambda contains real logic (multi-line bodies, multiple calls, branching, pattern matching with side effects), the anonymous-function form is correct.
- Use `then/2` to adapt shapes mid-pipeline when the next function does not accept the threaded value as its first argument or when the value needs wrapping.
- Use `tap/2` for in-chain side effects (logging, telemetry, debug taps). `tap/2` returns its input unchanged, making the in-chain side-effectful nature explicit.

## DO

```elixir
# lib/my_app/filters.ex - pipeline expresses sequential transformation
defmodule MyApp.Filters do
  def serialize(filters) do
    filters
    |> Enum.reject(&match?({_, nil}, &1))
    |> Enum.into(%{})
    |> URI.encode_query()
  end
end
```

```elixir
# lib/my_app/catalog.ex - captures for thin wrappers
Enum.map(items, &String.upcase/1)
Enum.map(items, &MyApp.Catalog.find_item(&1, org_id))
Enum.reduce(events, %{}, &Map.put(&2, &1.id, &1))
```

```elixir
# lib/my_app/accounts.ex - then/2 adapts shape mid-pipeline
def fetch(id) do
  id
  |> Repo.get(MyApp.Account)
  |> normalize()
  |> then(&{:ok, &1})
end
```

```elixir
# lib/my_app/events.ex - tap/2 for in-chain side effects
def process(input, opts) do
  input
  |> normalize()
  |> tap(&log_received/1)
  |> validate()
  |> tap(fn validated -> :telemetry.execute([:my_app, :validated], %{}, validated) end)
  |> persist(opts)
end
```

## DON'T

```elixir
# Why wrong: rebinding the same name across lines. Reader must track which
# `filters` is bound at each line. A bare statement between bindings is
# structurally indistinguishable from a real transformation.
defmodule MyApp.Filters do
  def serialize(filters) do
    filters = Enum.reject(filters, &match?({_, nil}, &1))
    filters = Enum.into(filters, %{})
    URI.encode_query(filters)
  end
end
```

```elixir
# Why wrong: anonymous-function wrapper around a single call. Introduces a
# binding (item, event) with no role beyond passing through.
Enum.map(items, fn item -> String.upcase(item) end)
Enum.reduce(events, %{}, fn event, acc -> Map.put(acc, event.id, event) end)
```

```elixir
# Why wrong: chain broken to bind an intermediate for one line of use,
# then wrap it as a separate statement. then/2 keeps the pipe whole.
def fetch(id) do
  account =
    id
    |> Repo.get(MyApp.Account)
    |> normalize()

  {:ok, account}
end
```

```elixir
# Why wrong: drops the threaded value to call a side effect inline, then
# resumes by rebinding. Structural signal that the side effect is in-chain
# and the value passes through unchanged is lost.
def process(input, opts) do
  normalized = normalize(input)
  log_received(normalized)
  validated = validate(normalized)
  :telemetry.execute([:my_app, :validated], %{}, validated)
  persisted = persist(validated, opts)
  persisted
end
```

## Applies To
- `lib/**/*.ex`
- `apps/*/lib/**/*.ex`
