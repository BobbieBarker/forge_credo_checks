---
type: adr
id: 4
title: Never Block the GenServer Processing Loop
status: accepted
date: 2026-04-22
tags: [elixir, otp, genserver, performance, callbacks]
description: GenServer callbacks handle one message at a time. Blocking I/O or unbounded computation in a callback stalls every other caller. Raising the call timeout papers over the problem instead of fixing it.
---
# ADR-004: Never Block the GenServer Processing Loop

GenServer callbacks return quickly. Blocking I/O or unbounded computation in a callback body stalls the mailbox for every other caller.

## Context

- A GenServer pulls one message at a time from its mailbox; each callback runs to completion before the next message is processed.
- A blocking HTTP call, a slow DB query, or any computation with a long tail freezes every other caller for the duration.
- Raising the `GenServer.call/2` timeout (or passing `:infinity`) does not make the server faster; it makes failures louder and harder to bound.
- At scale this cascades: mailbox grows, GC scans it, `process_info` degrades against long mailboxes (OTP issues #5481, #6494), and selective receive against a long queue becomes "very expensive" per the Erlang Efficiency Guide. The node stays nominally alive while throughput collapses.

## Consequence

- Mailbox depth is driven by request rate, not by tail latency inside the server.
- Caller timeouts stay at the default `5000` ms. When they fire, they point to a real problem rather than a tuned dial.
- Slow work moves to tasks, `handle_continue`, or async-reply patterns (see ADR-005).

## Rules

- No blocking I/O or unbounded computation in callbacks. "Quickly" means bounded and predictable, not "fast in the happy case."
- Do not raise the `GenServer.call/2` timeout to paper over a slow callback. The fix is to speed up the callback.
- `:infinity` on `GenServer.call/2` is almost never correct: a stuck upstream becomes a permanently stuck caller.

## DO

```elixir
# lib/my_app/inventory/server.ex - delegate slow work to a task and reply async
def handle_call({:reserve, sku, qty}, from, state) do
  Task.Supervisor.start_child(MyApp.TaskSupervisor, fn ->
    result = external_reserve(sku, qty)
    GenServer.reply(from, result)
  end)
  {:noreply, state}
end
```

```elixir
# lib/my_app/pricing.ex - default 5000 ms call timeout, no override
def fetch_price(sku), do: GenServer.call(MyApp.Pricing.Server, {:fetch, sku})
```

## DON'T

```elixir
# Why wrong: HTTP request runs inside the callback. Every other caller waits
# for the upstream's tail latency. The default 5000 ms timeout starts firing
# `:exit` across the codebase.
def handle_call({:reserve, sku, qty}, _from, state) do
  {:ok, response} = HTTPoison.get("https://inventory.example.com/reserve/#{sku}/#{qty}")
  {:reply, parse_response(response), state}
end
```

```elixir
# Why wrong: raising the timeout hides a slow callback and extends the blast
# radius. If 5000 ms is routinely not enough, the callback is doing work it
# should not be doing inline.
def fetch_price(sku), do: GenServer.call(MyApp.Pricing.Server, {:fetch, sku}, 60_000)
```

## Applies To
- `lib/**/*_server.ex`
- `apps/*/lib/**/*_server.ex`
