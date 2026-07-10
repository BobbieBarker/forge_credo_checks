---
type: adr
id: 1
title: Reach for Simpler Primitives Before GenServer
status: accepted
date: 2026-04-17
tags: [elixir, otp, genserver, concurrency, architecture]
description: GenServer serializes callers through a single mailbox. Use it only when that property is required. Default to plain modules, Agent, Task, Registry, or ETS.
---
# ADR-001: Reach for Simpler Primitives Before GenServer

GenServer serializes callers through a single mailbox. Reach for it only when that property is required. Default to plain modules, `Agent`, `Task`, `Registry`, or ETS.

## Context

- A GenServer has one mailbox; every call queues behind every other message.
- Most "stateful or service-shaped" code does not need that serialization.
- Reaching for GenServer when a simpler primitive fits adds a process lifecycle, a supervision decision, and a single-point bottleneck.
- Pure logic inside a GenServer can only be tested by starting a process.

## Consequence

- Work the ladder. Pick the first primitive that fits the problem.
- Most code previously written as a GenServer becomes a plain module, `Agent`, `Task`, `Registry`, or ETS-backed code.
- The GenServers that remain are load-bearing, and their presence signals genuine need.

## Rules

- Plain module for pure functions: stateless, no coordination.
- `Agent` for simple shared state: read or replace a value.
- `Task` / `Task.Supervisor` for concurrent work: process lifetime matches a unit of work.
- `Registry` for named-process lookup: keys to PIDs with monitor-driven cleanup.
- ETS (with an owning process for lifecycle) for shared, concurrent-read state.
- GenServer only when one of: serialized access to mutable state with multi-field invariants ETS atomics cannot preserve; serialized access to a scarce resource (TCP, file handle, rate-limited API); long-lived coordination combining calls, casts, `handle_info`, timers, and monitors.

## DO

```elixir
# lib/my_app/pricing.ex - pure module, no process needed
defmodule MyApp.Pricing do
  def calculate_total(items, discount_code) do
    items
    |> Enum.map(&item_total/1)
    |> Enum.sum()
    |> apply_discount(discount_code)
  end
end
```

```elixir
# lib/my_app/feature_flags.ex - Agent fits the get/update shape
defmodule MyApp.FeatureFlags do
  def start_link(initial),
    do: Agent.start_link(fn -> initial end, name: __MODULE__)

  def enabled?(flag), do: Agent.get(__MODULE__, &Map.get(&1, flag, false))
  def set(flag, value), do: Agent.update(__MODULE__, &Map.put(&1, flag, value))
end
```

```elixir
# lib/my_app/email_dispatch.ex - Task.Supervisor for concurrent work
def send_welcome_emails(users) do
  MyApp.TaskSupervisor
  |> Task.Supervisor.async_stream_nolink(users, &Mailer.send_welcome/1, max_concurrency: 10)
  |> Enum.to_list()
end
```

```elixir
# lib/my_app/flag_store.ex - ETS for concurrent-read state, GenServer owns lifecycle
defmodule MyApp.FlagStore do
  use GenServer
  @table :feature_flags

  def start_link(initial), do: GenServer.start_link(__MODULE__, initial, name: __MODULE__)
  def enabled?(flag), do: :ets.lookup_element(@table, flag, 2, false)
  def set(flag, value), do: GenServer.call(__MODULE__, {:set, flag, value})

  def init(initial) do
    :ets.new(@table, [:named_table, :protected, read_concurrency: true])
    Enum.each(initial, fn {k, v} -> :ets.insert(@table, {k, v}) end)
    {:ok, nil}
  end

  def handle_call({:set, flag, value}, _from, state) do
    :ets.insert(@table, {flag, value})
    {:reply, :ok, state}
  end
end
```

## DON'T

```elixir
# Why wrong: GenServer wrapping a pure computation. Adds mailbox serialization
# to work that does not require it. Calls queue behind unrelated traffic.
defmodule MyApp.Pricing do
  use GenServer

  def start_link(_), do: GenServer.start_link(__MODULE__, nil, name: __MODULE__)
  def calculate_total(items, code), do: GenServer.call(__MODULE__, {:calc, items, code})

  def init(_), do: {:ok, nil}

  def handle_call({:calc, items, code}, _from, state) do
    total = items |> Enum.map(&item_total/1) |> Enum.sum() |> apply_discount(code)
    {:reply, total, state}
  end
end
```

```elixir
# Why wrong: GenServer for keys-to-PIDs lookup. Every read queues behind a
# single mailbox. Registry uses per-shard ETS for concurrent reads and
# monitors registered processes to clean up automatically.
defmodule MyApp.SessionManager do
  use GenServer

  def start_link(_), do: GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  def lookup(id), do: GenServer.call(__MODULE__, {:lookup, id})
  def register(id, pid), do: GenServer.call(__MODULE__, {:register, id, pid})

  def init(state), do: {:ok, state}
  def handle_call({:lookup, id}, _from, state), do: {:reply, Map.get(state, id), state}
  def handle_call({:register, id, pid}, _from, state), do: {:reply, :ok, Map.put(state, id, pid)}
end
```

## Applies To
- `lib/**/*.ex`
- `apps/*/lib/**/*.ex`
