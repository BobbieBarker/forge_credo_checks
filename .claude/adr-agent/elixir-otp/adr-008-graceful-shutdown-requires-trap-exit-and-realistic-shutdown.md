---
type: adr
id: 8
title: Graceful Shutdown Requires trap_exit and a Realistic :shutdown
status: accepted
date: 2026-04-22
tags: [elixir, otp, genserver, shutdown, supervision]
description: terminate/2 only runs in three specific cases and never on brutal kills. Trap exits in init/1 if you need cleanup on supervisor :shutdown. Set a realistic :shutdown value. Do not treat terminate/2 as durable storage.
---
# ADR-008: Graceful Shutdown Requires trap_exit and a Realistic :shutdown

`terminate/2` is a best-effort cooperative shutdown hook, not a persistence layer. Trap exits if cleanup must run; keep `:shutdown` realistic; write critical state synchronously, not at exit.

## Context

- `terminate/2` runs in three cases: a callback returns `{:stop, _, _}`; a callback raises; or the process is trapping exits and receives an exit signal.
- `terminate/2` does NOT run on `Process.exit(pid, :kill)`, supervisor `:brutal_kill`, VM hard shutdown, or OS SIGKILL.
- A server that does not trap exits dies on supervisor `:shutdown` before `terminate/2` fires.
- The `:shutdown` value in the child spec is an upper bound, defaulting to 5000 ms. Padding it directly inflates deploy time and time-to-recovery.

## Consequence

- Servers that need graceful cleanup explicitly trap exits and declare their `:shutdown` budget.
- Servers that do not need graceful cleanup continue to crash cleanly and do not trap.
- Critical data writes happen synchronously, not lazily at shutdown.
- Long `:shutdown` timeouts are treated as a structural problem (move work upstream, see ADR-003), not a knob to tune.

## Rules

- Trap exits in `init/1` only if `terminate/2` must run on normal supervisor `:shutdown`. `Process.flag(:trap_exit, true)`.
- Servers with no cleanup work do not trap. Crashing cleanly is a feature.
- Do not pad the `:shutdown` timeout. Default `5000` ms is fine for almost every server. `:infinity` removes the supervisor's ability to recover from a stuck server.
- Do not treat `terminate/2` as durable storage. Critical state writes happen synchronously at the moment they matter, not buffered in memory and flushed at exit.

## DO

```elixir
# lib/my_app/buffered/server.ex - trap exits, flush on cooperative shutdown
def init(opts) do
  Process.flag(:trap_exit, true)
  {:ok, Impl.initial_state(opts)}
end

def terminate(_reason, state) do
  Buffer.flush(state.buffer)
  :ok
end
```

```elixir
# lib/my_app/event_log/server.ex - durable write happens before reply,
# not at terminate
def handle_call({:append, entry}, _from, state) do
  :ok = MyApp.EventLog.append(entry)
  {:reply, :ok, state}
end

def terminate(_reason, state) do
  :ok = MyApp.EventLog.flush_metadata(state.session_id)
end
```

```elixir
# lib/my_app/ingest/server.ex - default :shutdown of 5000 ms
defmodule MyApp.Ingest.Server do
  use GenServer
end
```

## DON'T

```elixir
# Why wrong: server does not trap exits. Supervisor :shutdown kills the
# process before terminate/2 runs. The cleanup code is dead code.
def init(opts) do
  {:ok, Impl.initial_state(opts)}
end

def terminate(_reason, state) do
  Buffer.flush(state.buffer)
end
```

```elixir
# Why wrong: padded to 30 seconds "to be safe." Across N nodes in a rolling
# deploy this directly inflates deploy time. During an incident it inflates
# time-to-recovery. ":infinity" is worse: a stuck server stalls the entire
# supervisor tree.
def child_spec(opts) do
  %{
    id: __MODULE__,
    start: {__MODULE__, :start_link, [opts]},
    shutdown: 30_000
  }
end
```

```elixir
# Why wrong: entries accumulate in memory and are only written on shutdown.
# Process.exit(pid, :kill), :brutal_kill, VM crash, or SIGKILL skip
# terminate/2 entirely; everything in buffered_entries is lost.
def handle_call({:append, entry}, _from, state) do
  {:reply, :ok, %{state | buffered_entries: [entry | state.buffered_entries]}}
end

def terminate(_reason, state) do
  :ok = MyApp.EventLog.append_all(state.buffered_entries)
end
```

## Applies To
- `lib/**/*_server.ex`
- `apps/*/lib/**/*_server.ex`
