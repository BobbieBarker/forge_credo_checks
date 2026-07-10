---
type: adr
id: 2
title: Separate GenServer Business Logic From Server Mechanics
status: accepted
date: 2026-04-17
tags: [elixir, otp, genserver, architecture, testing]
description: "Split each GenServer into three modules across three files. The API module is the boundary callers depend on. The Server module holds GenServer callbacks. The Impl module holds pure functions over explicit state with no GenServer awareness."
---
# ADR-002: Separate GenServer Business Logic From Server Mechanics

Split every GenServer into three modules across three files: API (boundary), Server (callbacks), Impl (pure functions over explicit state).

## Context

- A single-module GenServer entangles three concerns that change independently: public API, server mechanics, business logic.
- Logic embedded in callbacks is only testable by starting a process.
- Callers that import the same module that does the work are tightly coupled to the implementation choice.
- A three-module split makes the implementation choice (GenServer vs library vs Agent) reversible without touching call sites.

## Consequence

- Callers `alias MyApp.Inventory` (the API) and never see `Inventory.Server` or `Inventory.Impl`.
- Logic tests run directly against `Impl` with explicit state. No `start_supervised!`, no async ceremony.
- Process-level tests cover only dispatch, startup, and `handle_info` paths.
- Moving logic between a GenServer and a plain library is a single-file edit at the API layer.

## Rules

- Three modules per GenServer, each in its own file: `MyApp.Inventory` (API, `lib/my_app/inventory.ex`), `MyApp.Inventory.Server` (callbacks, `lib/my_app/inventory/server.ex`), `MyApp.Inventory.Impl` (logic, `lib/my_app/inventory/impl.ex`).
- `Impl` has no GenServer awareness: takes explicit state, returns `{result, new_state}` (or equivalent), never `{:reply, _, _}` / `{:noreply, _}`, never accepts a `from` tuple.
- `Impl` may emit telemetry, read or write ETS tables, and call other modules. The non-negotiable is that it does not speak GenServer return tuples.
- Server callbacks are thin dispatchers: each callback calls one `Impl` function and wraps the result in the GenServer return tuple. No business logic in callback bodies.
- Callers depend on the API module, not the Server. `GenServer.call(MyApp.Inventory.Server, ...)` from outside `lib/my_app/inventory/` breaks the boundary.

## DO

```elixir
# lib/my_app/inventory.ex - API, the boundary callers depend on
defmodule MyApp.Inventory do
  alias MyApp.Inventory.Server

  def start_link(opts \\ %{}), do: Server.start_link(opts)
  def reserve(sku, qty, name \\ Server), do: GenServer.call(name, {:reserve, sku, qty})
end
```

```elixir
# lib/my_app/inventory/server.ex - thin dispatcher
defmodule MyApp.Inventory.Server do
  use GenServer
  alias MyApp.Inventory.Impl

  def start_link(opts \\ %{}) do
    opts = Map.put_new(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: opts.name)
  end

  def init(opts), do: {:ok, Impl.initial_state(opts)}

  def handle_call({:reserve, sku, qty}, _from, state) do
    {result, new_state} = Impl.reserve(state, sku, qty)
    {:reply, result, new_state}
  end
end
```

```elixir
# lib/my_app/inventory/impl.ex - pure state-in / state-out
defmodule MyApp.Inventory.Impl do
  def initial_state(opts),
    do: %{stock: Map.get(opts, :stock, %{}), reservations: %{}}

  def reserve(state, sku, qty) do
    case Map.get(state.stock, sku) do
      n when is_integer(n) and n >= qty ->
        new_state = %{
          state
          | stock: Map.update!(state.stock, sku, &(&1 - qty)),
            reservations: Map.update(state.reservations, sku, qty, &(&1 + qty))
        }
        {:ok, new_state}

      _ ->
        {{:error, :insufficient_stock}, state}
    end
  end
end
```

## DON'T

```elixir
# Why wrong: API, callbacks, and logic all jammed into one module. Callers
# import the work module. Logic tests must start a process. Restructuring
# state or dispatch touches logic.
defmodule MyApp.Inventory do
  use GenServer

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  def reserve(sku, qty), do: GenServer.call(__MODULE__, {:reserve, sku, qty})

  def init(opts), do: {:ok, %{stock: Map.get(opts, :stock, %{}), reservations: %{}}}

  def handle_call({:reserve, sku, qty}, _from, state) do
    case Map.get(state.stock, sku) do
      n when is_integer(n) and n >= qty ->
        new_state = %{state | stock: Map.update!(state.stock, sku, &(&1 - qty))}
        {:reply, :ok, new_state}

      _ ->
        {:reply, {:error, :insufficient_stock}, state}
    end
  end
end
```

```elixir
# Why wrong: Impl returns GenServer callback tuples and accepts `from`.
# Couples Impl to the callback it is invoked from. Tests cannot exercise
# Impl without a live process.
defmodule MyApp.Inventory.Impl do
  def reserve(state, sku, qty, from) do
    case Map.get(state.stock, sku) do
      n when is_integer(n) and n >= qty ->
        GenServer.reply(from, :ok)
        {:noreply, deduct_stock(state, sku, qty)}

      _ ->
        {:reply, {:error, :insufficient_stock}, state}
    end
  end
end
```

## Applies To
- `lib/**/*_server.ex`
- `lib/**/*_impl.ex`
- `apps/*/lib/**/*_server.ex`
- `apps/*/lib/**/*_impl.ex`
