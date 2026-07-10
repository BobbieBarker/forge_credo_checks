---
type: adr
id: 26
title: Oban Worker Conventions
status: accepted
date: 2026-05-08
tags: [elixir, oban, jobs, background, workers]
description: "Use Oban's return tuples per failure semantic: {:cancel, _} permanent, {:error, _} transient, {:snooze, _} rate-limited. Pattern-match args in perform/1 with a catch-all clause that cancels on malformed args. Args use string keys. Queue concurrency matches workload. Each deploying app has its own named Oban instance."
---
# 026: Oban Worker Conventions

Workers communicate failure semantics through Oban's return tuples. Pattern-match args in `perform/1`. String keys only. Queue concurrency matches workload. Named Oban instance per deploying app.

## Context

- Wrong return tuple silently changes job lifecycle: `{:error, _}` retries permanent failures forever, `{:cancel, _}` discards transient failures.
- Args are JSON-serialized; atom keys round-trip as strings, so workers pattern-matching on atoms break on replay.
- Queue concurrency tuned by feel produces resource contention (CPU saturation when PDF generation runs at 50, memory exhaustion when CSV exports run at 100).
- Multi-app deployments need named Oban instances so jobs go to the right node and Repo connection pool.

## Consequence

- Worker `perform/1` returns one of `:ok`, `{:error, _}`, `{:cancel, _}`, `{:snooze, _}` per failure semantic.
- Every worker has at least two `perform/1` clauses: expected args + catch-all that cancels on malformed args.
- Args at every site (enqueue, pattern match, inspection) use string keys.
- Queue names describe workload (`:emails`, `:rendering`, `:stripe_api`); concurrency is set per workload with a comment naming why.
- Each deploying app has its own named Oban instance; workers specify which instance to insert into.

## Rules

- `{:cancel, reason}` for permanent failures (invalid args, deleted records, business rule violations). Never retried.
- `{:error, reason}` for transient failures (API timeout, network, DB lock). Retried if attempts remain.
- `{:snooze, seconds}` for rate-limited retries (Retry-After). Attempt is NOT consumed.
- `:ok` or `{:ok, _}` for success. Value is ignored.
- Pattern-match expected args shape in `perform/1` head. Add a catch-all `def perform(%Oban.Job{args: args}), do: {:cancel, "invalid args: #{inspect(Map.keys(args))}"}`.
- Args use string keys at every site (enqueue, pattern match). Atom keys break on replay because JSON has no atom representation.
- Queue concurrency matches workload type: I/O-bound high (5-20), CPU-intensive low (1-3), memory-intensive low, rate-limited per provider limit, serialized work concurrency 1.
- Each deploying app has its own named Oban instance. Workers specify the instance at insert time: `Oban.insert(MyAppWeb.Oban, job)`.
- Test with `assert_enqueued/1` and `perform_job/2`. Configure `testing: :manual` so jobs insert but do not execute until the test calls them.

## DO

```elixir
defmodule MyApp.Workers.SendInviteEmail do
  use Oban.Worker, queue: :emails, max_attempts: 5

  alias MyApp.{Accounts, Mailer}

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"invite_id" => id}}) when is_integer(id) do
    case Accounts.find_invite(%{id: id}) do
      {:ok, %{revoked_at: nil} = invite} ->
        case Mailer.deliver(InviteEmail.render(invite)) do
          {:ok, _} -> :ok
          {:error, %Mailer.RateLimitError{retry_after_ms: ms}} -> {:snooze, div(ms, 1000)}
          {:error, %Mailer.TransportError{}} -> {:error, "transport failed"}
        end

      {:ok, %{revoked_at: _}} ->
        {:cancel, "invite #{id} was revoked"}

      {:error, %ErrorMessage{code: :not_found}} ->
        {:cancel, "invite #{id} not found"}
    end
  end

  def perform(%Oban.Job{args: args}) do
    {:cancel, "invalid args: #{inspect(Map.keys(args))}"}
  end

  def enqueue(invite_id) do
    %{"invite_id" => invite_id}
    |> __MODULE__.new()
    |> Oban.insert(MyAppWeb.Oban)
  end
end
```

```elixir
# config/runtime.exs
# Example from Oban shadow — adapt paths to your project
config :my_app, MyAppWeb.Oban,
  repo: MyAppPG.Repo,
  queues: [
    emails: 10,        # I/O-bound: high concurrency
    webhooks: 20,      # I/O-bound: high concurrency
    rendering: 2,      # CPU-intensive: low to avoid scheduler contention
    csv_export: 2,     # Memory-intensive: low
    stripe_api: 5      # Rate-limited: matches Stripe's 100/sec
  ]
```

## DON'T

```elixir
# Why wrong: returns :ok regardless of mailer outcome (swallows failures).
# {:error, _} on not-found retries a job that will never succeed.
def perform(%Oban.Job{args: %{"invite_id" => id}}) do
  case Accounts.find_invite(%{id: id}) do
    {:ok, invite} ->
      Mailer.deliver(InviteEmail.render(invite))
      :ok

    {:error, _} ->
      {:error, "could not find invite"}
  end
end
```

```elixir
# Why wrong: atom keys break on replay (JSON deserializes to strings).
%{user_id: user.id} |> Worker.new() |> Oban.insert()

# Worker pattern-matches atoms, which works fresh but fails on retry.
def perform(%Oban.Job{args: %{user_id: id}}), do: ...
```

```elixir
# Why wrong: generic queue names with concurrency picked by feel.
queues: [default: 10, high: 50, background: 100]
```

## Applies To
- `apps/*/lib/**/workers/**/*.ex`
- `apps/*/lib/**/*_worker.ex`
- `lib/**/workers/**/*.ex`
- `lib/**/*_worker.ex`
