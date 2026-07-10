---
type: adr
id: 7
title: Telemetry Code Organization
status: accepted
date: 2026-05-08
tags: [elixir, telemetry, observability, organization]
description: "One metrics module per bounded context (`MyApp.Metrics.Auth`, `MyApp.Metrics.Billing`). Each exports `metrics/0` returning Telemetry.Metrics definitions plus measurement helpers business code calls. A single TelemetrySupervisor aggregates every context's `metrics/0`. Event names follow `[:app_name, :domain, :operation]`."
---
# 007: Telemetry Code Organization

Telemetry is organized as one metrics module per bounded context. Each module owns its event names, metric definitions, and measurement helpers; a single supervisor aggregates them.

## Context

- Scattering `:telemetry.execute/3` and `:telemetry.span/3` calls across business modules makes the metrics catalog impossible to read in one place.
- Metric definitions sprinkled inline in `application.ex` grow linearly with context count and force `application.ex` to know about every domain.
- A single supervised aggregator (`MyApp.TelemetrySupervisor`) lets new contexts add metrics without touching `application.ex`.

## Consequence

- Each bounded context has exactly one `MyApp.Metrics.*` module that owns its events and measurement helpers.
- `metrics/0` is the standard public API of every metrics module: it returns a list of `Telemetry.Metrics` definitions.
- A `MyApp.TelemetrySupervisor` aggregates per-context `metrics/0` into one combined list and starts the reporter.
- Adding a new metrics module is one line in the aggregator's `metrics/0` plus the new module file.

## Rules

- Each bounded context has one `MyApp.Metrics.<Context>` module owning every metric definition and measurement helper for that context.
- Each metrics module exports `metrics/0` returning a list of `Telemetry.Metrics` structs.
- A single `MyApp.TelemetrySupervisor` (or `MyApp.Telemetry`) supervises the reporter and composes per-context `metrics/0` outputs by `++`.
- Custom events follow `[:app_name, :domain, :operation]`. Spans auto-append `:start`/`:stop`/`:exception`; do not include those in the base name passed to `:telemetry.span/3`.
- Sub-domain operations may use a four-element list (`[:my_app, :billing, :invoice, :sent]`).
- Atom lists only. Strings in event names are anti-pattern.

## DO

```elixir
defmodule MyApp.Metrics.Webhooks do
  import Telemetry.Metrics

  def metrics do
    [
      counter("my_app.webhooks.delivery.count", tags: [:provider, :result]),
      distribution("my_app.webhooks.delivery.duration",
        unit: {:native, :millisecond},
        tags: [:provider, :result]
      )
    ]
  end

  def measure_delivery(provider, fun) do
    :telemetry.span([:my_app, :webhooks, :delivery], %{}, fn ->
      {result, ctx} = fun.()
      {result, Map.put(ctx, :provider, provider)}
    end)
  end
end

defmodule MyApp.TelemetrySupervisor do
  use Supervisor
  alias MyApp.Metrics

  def start_link(arg), do: Supervisor.start_link(__MODULE__, arg, name: __MODULE__)

  @impl true
  def init(_arg) do
    children = [{TelemetryMetricsPrometheus, metrics: metrics()}]
    Supervisor.init(children, strategy: :one_for_one)
  end

  defp metrics do
    Metrics.HTTP.metrics() ++
      Metrics.Auth.metrics() ++
      Metrics.Billing.metrics() ++
      Metrics.Webhooks.metrics()
  end
end
```

## DON'T

```elixir
# Why wrong: per-metric functions force the aggregator to enumerate names.
defmodule MyApp.Metrics.Billing do
  def charge_count_metric, do: counter("my_app.billing.charge.count", ...)
  def charge_duration_metric, do: distribution("my_app.billing.charge.duration", ...)
end
```

```elixir
# Why wrong: inline metric definitions in application.ex grow linearly with contexts.
def start(_, _) do
  children = [
    {TelemetryMetricsPrometheus,
     metrics: [
       counter("my_app.auth.login.count", tags: [:result]),
       distribution("my_app.auth.login.duration", tags: [:result]),
       counter("my_app.billing.charge.count", tags: [:provider, :result]),
       # ...fifty more inline...
     ]}
  ]

  Supervisor.start_link(children, strategy: :one_for_one)
end
```

```elixir
# Why wrong: span name includes :start, producing malformed [:my_app, :auth, :login, :start, :start]
:telemetry.span([:my_app, :auth, :login, :start], %{}, fun)
```

## Applies To
- `lib/**/metrics/**/*.ex`
- `lib/**/telemetry*.ex`
- `apps/*/lib/**/metrics/**/*.ex`
- `apps/*/lib/**/telemetry*.ex`
