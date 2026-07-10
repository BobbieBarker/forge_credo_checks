---
type: adr
id: 10
title: Test OTP Code Through Real Processes
status: accepted
date: 2026-05-08
tags: [elixir, otp, testing, sql-sandbox, callers]
description: "Use start_supervised!/1 for test-scoped processes. Test Impl callbacks directly when the GenServer is structured per ADR-002. Never manipulate library-owned process state via :sys. Application supervision is identical across environments. Know which OTP primitives propagate $callers for SQL Sandbox compatibility."
---
# ADR-010: Test OTP Code Through Real Processes

Tests exercise the real OTP machinery the production system uses. Spin up real processes through the standard supervisor, test pure logic without processes when the design allows, and never reach into library internals.

## Context

- A globally-named GenServer that persists across the suite shares state with every other test that touches it.
- `:sys.replace_state` on a library-owned process corrupts internal invariants the library depends on across its own callbacks.
- An `application.ex` that branches on `Mix.env()` means the system being tested is not the system that runs in production.
- `Phoenix.Ecto.SQL.Sandbox` uses `$callers` (a process-dictionary key) to resolve which test process owns a database connection. When the chain breaks, sandbox lookups fail and child processes hang or error.
- `$callers` propagates through `Task.async/1`, `Task.Supervisor.async_*`, and `start_supervised!/1`. It does NOT propagate through `GenServer.call/2`, `GenServer.cast/2`, `send/2`, or app-supervised processes.

## Consequence

- Process-level test setup is `start_supervised!/1`, not bare `start_link/1`. Tests are torn down deterministically and run `async: true`.
- Logic tests hit `Impl` modules directly. The bulk of an OTP module's test surface lives in `_impl_test.exs`, not `_server_test.exs`.
- Library-owned processes (`Phoenix.PubSub`, `Ecto.Repo` pools, `Oban` engines) are read-only as far as tests are concerned.
- `application.ex` is identical across environments. Per-test variance comes from opts injection, sandbox connections, and substitution at known boundaries.

## Rules

- Use `start_supervised!/1` for any process you spin up in a test. It tears down deterministically on test exit and propagates `$callers` to the started process.
- Test pure callback logic directly when the Impl pattern (ADR-002) makes it possible. Skip `start_supervised!` for these tests.
- Never manipulate library-owned process state with `:sys.replace_state` or `:sys.get_state`. Library-owned processes hold invariants the library depends on; the API is the test surface.
- `application.ex` must not branch by environment. Test-specific behavior comes from per-test opts injection (ADR-007) and per-test sandbox configuration.
- Know which OTP primitives propagate `$callers`. When a test depends on database access from a child process, structure the spawn through one of the propagating primitives, or use `Ecto.Adapters.SQL.Sandbox.allow/3` to grant the child explicit access.

## DO

```elixir
# test/my_app/inventory/server_test.exs - start_supervised!, unique name,
# async: true
defmodule MyApp.Inventory.ServerTest do
  use ExUnit.Case, async: true
  alias MyApp.Inventory.Server

  setup do
    name = :"inventory_#{System.unique_integer([:positive])}"
    start_supervised!({Server, %{name: name}})
    {:ok, server: name}
  end

  test "reserves stock", %{server: server} do
    assert {:ok, _id} = Server.reserve(server, "sku-1", 3)
  end
end
```

```elixir
# test/my_app/inventory/impl_test.exs - test Impl as pure functions
defmodule MyApp.Inventory.ImplTest do
  use ExUnit.Case, async: true
  alias MyApp.Inventory.Impl

  test "reserve deducts stock when available" do
    state = %{stock: %{"sku-1" => 5}, reservations: %{}}
    assert {:ok, new_state} = Impl.reserve(state, "sku-1", 3)
    assert new_state.stock == %{"sku-1" => 2}
  end
end
```

```elixir
# lib/my_app/application.ex - identical supervision tree across environments
defmodule MyApp.Application do
  use Application

  @impl true
  def start(_type, _args) do
    children = [
      MyApp.Repo,
      MyAppWeb.Endpoint,
      {Task.Supervisor, name: MyApp.TaskSupervisor},
      MyApp.Inventory.Server
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: MyApp.Supervisor)
  end
end
```

```elixir
# test/my_app/scans_test.exs - Task.Supervisor.async_nolink propagates
# $callers so the child sees the test's SQL Sandbox connection
test "fans out scan recording across tasks" do
  supervisor = start_supervised!({Task.Supervisor, []})

  Task.Supervisor.async_nolink(supervisor, fn -> MyApp.Scans.record(scan) end)
  |> Task.await()

  assert [%Scan{}] = MyApp.Scans.list()
end
```

## DON'T

```elixir
# Why wrong: bare start_link/1 leaks the process on test exit, blocks
# async: true (named-process slot is contended across the suite), and
# breaks $callers (the process is rooted in the test module rather than
# the test process).
defmodule MyApp.Inventory.ServerTest do
  use ExUnit.Case, async: false
  alias MyApp.Inventory.Server

  setup do
    {:ok, _pid} = Server.start_link(%{name: __MODULE__})
    :ok
  end
end
```

```elixir
# Why wrong: :sys.replace_state on a library-owned process. The library's
# next message can fail in ways that have nothing to do with the test's
# intent and everything to do with the surgery the test performed.
test "force-complete job via state surgery" do
  state = :sys.get_state(Oban.Pro.Engines.Smart)
  modified = put_in(state, [:queues, :default, :running], %{"abc" => :completed})
  :sys.replace_state(Oban.Pro.Engines.Smart, fn _ -> modified end)
end
```

```elixir
# Why wrong: branching the supervision tree by environment. The system
# being tested differs from the system that runs in production.
def start(_type, _args) do
  children =
    if Mix.env() === :test do
      [MyApp.Repo, MyAppWeb.Endpoint]
    else
      [MyApp.Repo, MyAppWeb.Endpoint, MyApp.Inventory.Server, MyApp.PollLoop]
    end

  Supervisor.start_link(children, strategy: :one_for_one, name: MyApp.Supervisor)
end
```

```elixir
# Why wrong: send/2 does NOT propagate $callers. The child process cannot
# resolve the test's SQL Sandbox connection.
test "fans out scan recording across tasks" do
  send(MyApp.ScanWorker, {:record, scan})
  assert [%Scan{}] = MyApp.Scans.list()
end
```

## Applies To
- `test/**/*_test.exs`
- `apps/*/test/**/*_test.exs`
- `lib/**/application.ex`
- `apps/*/lib/**/application.ex`
