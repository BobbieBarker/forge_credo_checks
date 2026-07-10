---
type: adr
id: 5
title: Get Slow Work Off the Processing Loop
status: accepted
date: 2026-04-22
tags: [elixir, otp, genserver, handle_continue, task, async]
description: Three OTP mechanisms for moving slow work out of a GenServer callback. handle_continue/2 for post-init deferred work, Task.Supervisor for fire-and-forget, GenServer.reply/2 for async responses.
---
# ADR-005: Get Slow Work Off the Processing Loop

Slow work runs outside the callback body. Use `handle_continue/2` for post-init, `Task.Supervisor` for fire-and-forget, `GenServer.reply/2` for async responses.

## Context

- ADR-004 forbids blocking the callback. This ADR names the three OTP mechanisms for doing the slow work elsewhere.
- `handle_continue/2`: deferred work that must run before the first client message but should not block `init/1` (and the supervisor's `start_link` waiting on it).
- `Task.Supervisor`: fire-and-forget work whose result is not needed in line, with structured supervision and crash reporting.
- `GenServer.reply/2`: work that must return to the original caller but cannot run inline.

## Consequence

- Callbacks stay bounded regardless of how slow the underlying work is.
- Expensive init runs without blocking the supervisor tree.
- Fire-and-forget work is supervised, not lost.

## Rules

- Use `handle_continue/2` for post-init work. Return `{:ok, state, {:continue, term}}` from `init/1` and run the heavy setup in `handle_continue(term, state)`.
- Use `Task.Supervisor.start_child/2` for fire-and-forget work. Use `Task.Supervisor.async_nolink/3` when the result must arrive later as a `handle_info({ref, result}, state)` message.
- Never use `spawn/1` or `spawn_link/1` for fire-and-forget: no supervision, no error reporting, and `spawn_link` takes the server down with the child.
- Use `GenServer.reply/2` for async responses: return `{:noreply, state}` from `handle_call`, kick the work to a task, and call `GenServer.reply(from, result)` from the task.

## DO

```elixir
# lib/my_app/catalog/server.ex - handle_continue for expensive init
def init(opts) do
  {:ok, Impl.initial_state(opts), {:continue, :load_catalog}}
end

def handle_continue(:load_catalog, state) do
  {:ok, catalog} = load_catalog_from_disk(state.config.catalog_path)
  {:noreply, %{state | catalog: catalog}}
end
```

```elixir
# lib/my_app/audit/server.ex - Task.Supervisor for fire-and-forget
def handle_cast({:emit_audit_event, event}, state) do
  Task.Supervisor.start_child(MyApp.TaskSupervisor, fn ->
    AuditLog.send(event)
  end)
  {:noreply, state}
end
```

```elixir
# lib/my_app/reconciliation/server.ex - GenServer.reply for async response
def handle_call({:reconcile, account_id}, from, state) do
  Task.Supervisor.start_child(MyApp.TaskSupervisor, fn ->
    result = do_reconciliation(account_id)
    GenServer.reply(from, result)
  end)
  {:noreply, state}
end
```

## DON'T

```elixir
# Why wrong: expensive disk I/O inside init/1 blocks the supervisor's
# start_link call. Every dependent child waits.
def init(opts) do
  state = Impl.initial_state(opts)
  {:ok, catalog} = load_catalog_from_disk(state.config.catalog_path)
  {:ok, %{state | catalog: catalog}}
end
```

```elixir
# Why wrong: spawn/1 has no supervision, no structured error reporting, and
# no way to bound concurrency. A crash disappears silently.
def handle_cast({:emit_audit_event, event}, state) do
  spawn(fn -> AuditLog.send(event) end)
  {:noreply, state}
end
```

```elixir
# Why wrong: synchronous reconciliation inside the callback. Stalls every
# other caller for the duration of the work.
def handle_call({:reconcile, account_id}, _from, state) do
  result = do_reconciliation(account_id)
  {:reply, result, state}
end
```

## Applies To
- `lib/**/*_server.ex`
- `apps/*/lib/**/*_server.ex`
