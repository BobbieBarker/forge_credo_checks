---
type: adr
id: 3
title: Keep GenServer State Small; Push Storage Out of Process
status: accepted
date: 2026-04-18
tags: [elixir, otp, genserver, performance, state, gc]
description: GC pauses scale with a process's live heap. A GenServer's state holds coordination and identity, not bulk data. Bulk data belongs in ETS, Postgres, Redis, or a cache abstraction.
---
# ADR-003: Keep GenServer State Small; Push Storage Out of Process

A GenServer's state represents what the process coordinates, not what the process stores. Bulk data lives outside the process.

## Context

- BEAM uses per-process heaps with a generational semi-space collector. GC pauses scale with the live heap of the process being collected.
- A GenServer holding bulk data (a large map, a growing cache, accumulated history) pays GC pauses on that one process. Tail latency on one endpoint, hard to attribute.
- Storage that needs concurrent reads belongs in ETS, Postgres, Redis, or a cache abstraction. The server's state holds the identity and in-flight coordination only.

## Consequence

- Most GenServer state shrinks to coordination metadata. The process no longer dominates its own GC cost.
- Reads of bulk data go to a shared store with concurrent-read semantics, not through the server mailbox.
- Configuration is parsed once at init; the working state is what changes as the server runs.

## Rules

- Push bulk data out of the process. Data that grows with usage (entries, caches, batches, event history) lives outside the process struct.
- Separate working state from configuration state. Model `config` (stable, parsed once) and the mutable working fields as distinct fields of the state struct (or distinct modules).
- Default to off-process storage. Justify in-process state when you keep it. The burden of proof is on keeping data in.
- Legitimate exceptions: state that must be strictly mailbox-ordered and would lose ordering in ETS with concurrent writers; derived state whose recomputation is more expensive than the GC cost; genuinely small state (a flag, a counter, a struct with a handful of fields).

## DO

```elixir
# lib/my_app/inventory/impl.ex - bulk data out, coordination state in
defmodule MyApp.Inventory.Impl do
  def initial_state(%{name: name}) do
    %{
      name: name,
      pending_reservations: %{}
    }
  end

  def reserve(state, sku, qty) do
    case MyApp.Inventory.Cache.get(sku) do
      n when is_integer(n) and n >= qty ->
        :ok = MyApp.Inventory.Cache.decrement(sku, qty)
        reservation_id = System.unique_integer([:positive])
        new_state = put_in(state, [:pending_reservations, reservation_id], {sku, qty})
        {{:ok, reservation_id}, new_state}

      _ ->
        {{:error, :insufficient_stock}, state}
    end
  end
end
```

```elixir
# lib/my_app/rate_limiter/config.ex - parse once at init
defmodule MyApp.RateLimiter.Config do
  defstruct [:window_ms, :max_requests, :buckets_per_key]

  def from(opts) do
    %__MODULE__{
      window_ms: duration_to_ms(Map.get(opts, :window, "10s")),
      max_requests: Map.get(opts, :max_requests, 100),
      buckets_per_key: Map.get(opts, :buckets, 10)
    }
  end
end

defmodule MyApp.RateLimiter.Impl do
  alias MyApp.RateLimiter.Config

  def initial_state(opts) do
    %{
      config: Config.from(opts),
      in_flight: %{}
    }
  end
end
```

## DON'T

```elixir
# Why wrong: full stock map and complete reservation history live on the
# server's heap. Every GC scans all of it. Every read queues behind every
# write through one mailbox.
defmodule MyApp.Inventory.Impl do
  def initial_state(%{name: name}) do
    %{
      name: name,
      stock: load_all_stock_from_db(),
      pending_reservations: %{},
      completed_reservations: []
    }
  end

  def reserve(state, sku, qty) do
    case Map.get(state.stock, sku) do
      n when is_integer(n) and n >= qty ->
        {:ok, record_reservation(state, sku, qty)}

      _ ->
        {{:error, :insufficient_stock}, state}
    end
  end
end
```

```elixir
# Why wrong: configuration mixed with mutable working state. Reviewer must
# scan every callback to learn which fields change. "10s" is re-parsed on
# every request instead of converted once at init.
defmodule MyApp.RateLimiter.Impl do
  def initial_state(opts) do
    %{
      window: Map.get(opts, :window, "10s"),
      max_requests: Map.get(opts, :max_requests, 100),
      buckets: Map.get(opts, :buckets, 10),
      in_flight: %{}
    }
  end
end
```

## Applies To
- `lib/**/*_impl.ex`
- `lib/**/*_server.ex`
- `apps/*/lib/**/*_impl.ex`
- `apps/*/lib/**/*_server.ex`
