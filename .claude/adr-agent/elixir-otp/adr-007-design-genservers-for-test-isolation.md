---
type: adr
id: 7
title: Design GenServers for Test Isolation
status: accepted
date: 2026-04-29
tags: [elixir, otp, genserver, testing, dependency-injection]
description: "Every GenServer accepts a configurable :name and validates opts at start. When the server has substitutable collaborators or owns storage, inject them via opts (preferred over Mox) and use a cache library with a sandbox adapter for storage. Mox is reserved for external boundaries (HTTP, clocks, third-party SDKs)."
---
# ADR-007: Design GenServers for Test Isolation

Every GenServer accepts a configurable `:name` and validates opts at start. Substitutable collaborators are injected via opts. Storage uses a cache library with a sandbox adapter. Mox is reserved for external boundaries.

## Context

- A server registered under a fixed `__MODULE__` atom can only exist once per VM. Tests serialize against each other or share state.
- Validating opts inside `init/1` (or skipping validation) lets a typo become a production bug. NimbleOptions declares the contract once with required keys, types, defaults, and docs.
- Hardcoded collaborators force tests into `Application.put_env` hacks or Mox-against-undeclared-behaviours. Opts injection keeps the choice at the call site.
- Hand-rolled `:ets.new(:named_table)` inside `init/1` collides across tests. A cache library with a sandbox adapter (`elixir_cache`) gives each test an isolated namespace.

## Consequence

- Every GenServer takes a configurable name and is testable in isolation.
- Every GenServer fails fast on bad opts before it accepts traffic.
- Opts are maps everywhere: callers, `start_link`, `init`, `Impl`. Pattern matching is the default access mechanism.
- Tests run `async: true` by default. Per-test instances with stubbed collaborators are the norm.

## Rules

- Every GenServer accepts a configurable `:name` via opts. Production passes a default at the supervision tree; tests pass a unique atom per test.
- Pass opts as maps and validate with NimbleOptions. Declare `@opts_schema` as a module attribute, validate at the boundary, return a map.
- Inject substitutable collaborators via opts when present (a cache, an external API client, a clock, a mailer). This rule does NOT apply to GenServers with no substitutable collaborators.
- Delegate storage to a cache library with a sandbox adapter when storage is present. Do not hand-roll `:ets.new(:named_table)` inside `init/1`. This rule does NOT apply when the server holds no storage of its own.
- Prefer opts injection over Mox for substitutable collaborators. Mox earns its overhead at external boundaries (HTTP APIs, clocks, third-party SDKs with stateful sessions). Internal collaborators are opts-injected.

## DO

```elixir
# lib/my_app/inventory/server.ex - configurable name, NimbleOptions schema,
# opts-injected cache
defmodule MyApp.Inventory.Server do
  use GenServer

  @opts_schema NimbleOptions.new!(
    name: [type: :any, required: true, doc: "Registered name."],
    threshold: [type: :pos_integer, default: 100, doc: "Mailbox shed threshold."],
    cache: [type: :atom, default: MyApp.Inventory.Cache, doc: "Cache module."]
  )

  def start_link(opts) when is_map(opts) do
    opts =
      opts
      |> Keyword.new()
      |> NimbleOptions.validate!(@opts_schema)
      |> Map.new()

    GenServer.start_link(__MODULE__, opts, name: opts.name)
  end

  def init(opts), do: {:ok, Impl.initial_state(opts)}
end
```

```elixir
# test/my_app/inventory/server_test.exs - per-test name, stubbed cache
setup do
  name = :"inventory_#{System.unique_integer([:positive])}"
  start_supervised!({MyApp.Inventory.Server, %{name: name, cache: StubCache}})
  {:ok, server: name}
end
```

```elixir
# lib/my_app/inventory/cache.ex - elixir_cache with sandbox adapter
defmodule MyApp.Inventory.Cache do
  use Cache,
    adapter: Cache.ETS,
    name: :inventory_cache,
    sandbox?: Mix.env() === :test,
    opts: []
end
```

## DON'T

```elixir
# Why wrong: __MODULE__ is registered globally. Two instances cannot
# coexist. Every test that starts the server blocks other tests or shares
# state with them.
defmodule MyApp.Inventory.Server do
  use GenServer

  def start_link(_opts), do: GenServer.start_link(__MODULE__, nil, name: __MODULE__)
end
```

```elixir
# Why wrong: hand-rolled validation accumulates special cases. A bad opt
# silently becomes the default; the bug surfaces in production.
def start_link(opts \\ []) do
  name = Keyword.get(opts, :name, __MODULE__)
  GenServer.start_link(__MODULE__, opts, name: name)
end

def init(opts) do
  {:ok, %{threshold: Keyword.get(opts, :threshold, 100)}}
end
```

```elixir
# Why wrong: ETS named_table collides across tests. No way to swap storage
# backends. Cleanup requires async: false.
def init(_) do
  :ets.new(:inventory_cache, [:named_table, :public, read_concurrency: true])
  {:ok, %{}}
end
```

```elixir
# Why wrong: Mox-against-undeclared-behaviour for a substitutable internal
# collaborator. Tests must mutate Application env or hand-roll a behaviour
# that does not exist. Opts injection covers this case directly.
@cache Application.compile_env(:my_app, :cache, MyApp.Inventory.Cache)

def handle_call({:get, key}, _from, state), do: {:reply, @cache.get(key), state}
```

## Applies To
- `lib/**/*_server.ex`
- `apps/*/lib/**/*_server.ex`
