---
type: adr
id: 5
title: Telemetry Scope
status: accepted
date: 2026-05-08
tags: [elixir, telemetry, observability]
description: "Don't re-instrument what frameworks already emit (Phoenix, LiveView, Ecto, Finch, Oban). Custom telemetry covers business-domain events only. Emit through metrics modules, not :telemetry calls in business logic. Use bounded-cardinality tags from a closed set; never tag with IDs, URLs, or user identifiers."
---
# 005: Telemetry Scope

Custom telemetry is for business-domain events the framework cannot see. Phoenix, LiveView, Ecto, Finch, and Oban already emit comprehensive lifecycle events; do not duplicate them in business logic.

## Context

- Phoenix emits the request lifecycle, controller actions, channels, sockets.
- LiveView emits per-callback timing for mount, handle_params, handle_event, render.
- Ecto fires events for every query with idle_time, queue_time, query_time, decode_time, total_time, SQL.
- Finch (Req's HTTP client) emits per-request lifecycle events including the `finch_private` map for service tagging.
- Oban emits start/stop/exception per job with duration, queue_time, memory.
- Custom events should appear only when the moment is a domain operation no framework can see (auth outcome, redirect resolution, webhook delivery, billing event, QR rendering).

## Consequence

- Reach for `Telemetry.Metrics` definitions attached to framework events first; only emit custom events when no framework event captures the moment.
- Business code calls measurement helpers on metrics modules (e.g. `Metrics.Auth.measure_login/2`); never `:telemetry.execute/3` or `:telemetry.span/3` directly inline.
- Tag values come from a closed set of atoms enumerated at the metrics-module level.
- High-cardinality fields (user IDs, request IDs, URLs) go in structured logs or trace spans, not in metric tags.

## Rules

- Before adding a telemetry event, check whether the framework already emits it. If so, attach a `Telemetry.Metrics` definition to the framework event in your metrics module instead.
- Custom events use the shape `[:app_name, :domain, :operation]`; spans auto-append `:start`, `:stop`, `:exception` (do not include those suffixes in the base name).
- Business logic calls measurement functions on `MyApp.Metrics.*` modules. Direct `:telemetry.execute/3` or `:telemetry.span/3` in domain code is anti-pattern.
- Tags must come from a closed set of atoms (status atoms, service identifiers, queue names, HTTP methods). Never tag with user IDs, request IDs, URLs with embedded path parameters, customer names, or any high-cardinality field.
- When a debugging investigation needs entity-level correlation, that goes through structured logs or a trace span, not through metric tags.

## DO

```elixir
defmodule MyApp.Metrics.Auth do
  import Telemetry.Metrics

  def metrics do
    [
      counter("my_app.auth.login.count", tags: [:result]),
      distribution("my_app.auth.login.duration", unit: {:native, :millisecond}, tags: [:result])
    ]
  end

  def measure_login(result, fun) when result in [:success, :failure, :rate_limited] do
    :telemetry.span([:my_app, :auth, :login], %{}, fn ->
      {fun.(), %{result: result}}
    end)
  end
end

defmodule MyApp.Auth do
  alias MyApp.Metrics.Auth, as: Metrics

  def login(email, password) do
    Metrics.measure_login(login_result_atom(email, password), fn ->
      do_login(email, password)
    end)
  end
end
```

## DON'T

```elixir
# Why wrong: re-instruments Phoenix request lifecycle.
def show(conn, params) do
  start = System.monotonic_time()
  user = Accounts.find_user(params["id"])
  :telemetry.execute(
    [:my_app, :web, :show, :duration],
    %{duration: System.monotonic_time() - start},
    %{path: "/users/:id"}
  )

  render(conn, "show.html", user: user)
end
```

```elixir
# Why wrong: high-cardinality tags (user_id, customer_email).
:telemetry.execute([:my_app, :payments, :charge], %{}, %{
  user_id: user.id,
  customer_email: user.email
})
```

```elixir
# Why wrong: :telemetry.execute/3 inline in business logic.
def login(email, password) do
  :telemetry.execute([:my_app, :auth, :login, :start], %{}, %{email: email})
  # ... work ...
  :telemetry.execute([:my_app, :auth, :login, :end], %{}, %{result: :success})
end
```

## Applies To
- `lib/**/*.ex`
- `apps/*/lib/**/*.ex`
