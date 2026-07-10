---
type: adr
id: 13
title: Config Module Convention
status: accepted
date: 2026-05-08
tags: [elixir, config, environment, application-env]
description: "Each app exposes a Config module as the sole boundary for environment access. Business logic never calls Application.get_env or System.get_env directly. Adapters wire at compile time via @adapter Config.adapter(). Application.compile_env stays at the use site (it cannot be wrapped in Config) with a one-line comment."
---
# 013: Config Module Convention

Every app has one `Config` module that owns environment access. Business code reads typed getter functions; the Config module is the only place that touches `Application.get_env/2`.

## Context

- Scattered `Application.get_env/2` and `System.get_env/1` calls in business logic create invisible runtime dependencies.
- Centralizing config access in a `Config` module exposes every read in one place, supports typed defaults, and enables compile-time adapter wiring.
- `runtime.exs` is the canonical place to read environment variables and write them into application config; the Config module reads from application config.
- `Application.compile_env/3` is evaluated at compile time and cannot be wrapped in a runtime function; it stays at the use site with a comment.

## Consequence

- Each app has one `<App>.Config` module exposing typed getter functions.
- `Application.get_env/2` and `System.get_env/1` calls outside `Config` modules and `runtime.exs` are anti-pattern.
- Adapters bind via `@adapter Config.adapter()` as a module attribute (compile-time, no runtime lookup on the hot path).
- `Application.compile_env/3` lives at the use site with a one-line comment naming why it cannot be in Config.

## Rules

- Each app has one `<App>.Config` module (e.g. `MyAppPayments.Config`). Marked `@moduledoc false`. Declares one `@app` attribute.
- Each Config function returns a typed value with a sensible default: `def adapter, do: Application.get_env(@app, :adapter, MyApp.Payments.StripeAdapter)`.
- Business logic does not call `Application.get_env/2` or `System.get_env/1` directly. All reads go through Config.
- Adapter wiring is `@adapter Config.adapter()` at compile time. Runtime adapter switching via `Config.adapter().some_function/N` on every call is anti-pattern.
- `Application.compile_env/3` stays at the use site, never wrapped in a Config function. Add a one-line comment naming why.
- Tests configure values via `config/test.exs`. `Application.put_env/3` in test bodies is a smell; prefer opts-injection.

## DO

```elixir
defmodule MyAppPayments.Config do
  @moduledoc false
  @app :my_app_payments

  def adapter, do: Application.get_env(@app, :adapter, MyAppPayments.StripeAdapter)
  def api_base_url, do: Application.get_env(@app, :api_base_url, "https://api.stripe.com/v1")
  def request_timeout_ms, do: Application.get_env(@app, :request_timeout_ms, 5_000)
end

defmodule MyAppPayments.StripeAdapter do
  alias MyAppPayments.Config

  def charge(amount, token) do
    HTTPClient.post(Config.api_base_url() <> "/charges",
      body: %{amount: amount, source: token},
      receive_timeout: Config.request_timeout_ms()
    )
  end
end

defmodule MyApp.Checkout do
  @adapter MyAppPayments.Config.adapter()

  defdelegate charge(amount, token), to: @adapter
end
```

```elixir
# Application.compile_env at the use site with a comment
defmodule MyApp.HTTPClient do
  # compile_env must be at the use site; Config wraps runtime reads only.
  @req_options Application.compile_env(:my_app, :req_options, [])

  def post(url, opts), do: Req.post(url, Keyword.merge(@req_options, opts))
end
```

## DON'T

```elixir
# Why wrong: Application.get_env and System.get_env scattered in business logic.
def charge(amount, token) do
  base_url = Application.get_env(:my_app_payments, :api_base_url, "https://api.stripe.com/v1")
  timeout = System.get_env("STRIPE_TIMEOUT_MS", "5000") |> String.to_integer()

  HTTPClient.post(base_url <> "/charges", body: ..., receive_timeout: timeout)
end
```

```elixir
# Why wrong: runtime adapter lookup on every call (Application.get_env every invocation).
def create_customer(params), do: Config.adapter().create_customer(params)
```

```elixir
# Why wrong: compile_env wrapped in a Config function. The compile-time
# introspection captures the wrong calling module.
defmodule Config do
  def req_options, do: Application.compile_env(@app, :req_options, [])
end
```

## Applies To
- `apps/*/lib/**/config.ex`
- `lib/**/config.ex`
- `lib/**/*config*.ex`
