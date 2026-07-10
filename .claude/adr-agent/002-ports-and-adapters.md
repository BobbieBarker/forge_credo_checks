---
type: adr
id: 2
title: Ports and Adapters
status: accepted
date: 2026-05-08
tags: [elixir, architecture, ports-adapters, hexagonal, external-services]
description: "Ports mark the boundary where internal models are serialized to external models, and external models are deserialized back before they enter the core."
---
# 002: Ports and Adapters

A port is the boundary where the system translates between internal models and external models. The invariant is
simple: external models never cross into the core un-deserialized, and core models never leak outward as vendor-shaped
payloads.

Ports-and-adapters is not a recipe that every external call must realize with a behaviour, adapter, serializer, Config
module, and compile-time module attribute. It is a boundary discipline. The implementation shape is earned by the
integration's variability, risk, and model translation needs.

## Context

- External systems speak in their own models: HTTP payloads, SDK structs, database rows, message schemas, files, CLI
  output, or protocol-specific error shapes.
- The core speaks in domain models and domain outcomes.
- The architectural risk is not "no behaviour exists." The risk is that external shapes become part of the core's
  public vocabulary.
- Over-applying ports-and-adapters creates ceremony, fake seams, and test indirection. That is a failure mode equal to
  under-applying the boundary and leaking vendor types.

## Consequence

- Serialization and deserialization sit at the boundary. Vendor field names, SDK structs, HTTP response maps, database
  row details, and wire-level error codes stay there.
- Core modules consume internal structs, internal maps with domain names, or explicit domain return shapes.
- A `@behaviour` is introduced when there are at least two real implementations of the same boundary contract. A Mox
  mock used for tests does not count as the second implementation.
- The database is already a concrete persistence boundary. Do not wrap normal Ecto context/schema/query code in a
  behaviour just because it touches Postgres.
- A single implementation with useful translation still needs containment, but not necessarily a behaviour.

## Realization Menu

- **Database-backed domain state:** use context/schema/query modules. Keep Ecto schemas, queries, Repo calls, and
  database row details inside the database layer. No behaviour is required for ordinary Postgres access.
- **Swappable vendor with two or more real implementations:** define a behaviour for the port contract, implement each
  vendor behind it, and keep serialization/deserialization at the adapter boundary.
- **Single vendor or single implementation:** use a containment module that owns the external model translation. Add a
  behaviour later when a second real implementation appears.
- **HTTP APIs:** build and parse requests at the HTTP boundary, normalize responses before returning to the core, and
  test the request/response boundary with the project's HTTP testing tool.
- **Test substitution:** Mox is appropriate when tests need to stand in for an external boundary contract. The existence
  of that mock does not by itself justify a production behaviour.

## Rules

- Name operations in domain terms, not vendor terms.
- Translate outbound internal models into external models at the boundary.
- Translate inbound external models into internal models before returning to core code.
- Keep vendor field names, SDK structs, raw HTTP bodies, Ecto row/query details, and external error codes out of core
  modules.
- Add a `@behaviour` only for a real multi-implementation contract. Do not create one to satisfy a template.
- Prefer a small containment module for a single implementation whose main job is translation.
- Treat needless behaviours, adapters, serializers, and config wiring as architectural debt when they do not buy
  substitutability or containment.

## DO

```elixir
defmodule MyApp.Billing.StripeBoundary do
  alias MyApp.Billing.Payment

  def create_payment(%Payment{} = payment) do
    payment
    |> to_stripe_request()
    |> MyApp.HTTP.post("/v1/payment_intents")
    |> from_stripe_response()
  end

  defp to_stripe_request(%Payment{} = payment) do
    %{
      "amount" => payment.amount_cents,
      "currency" => payment.currency
    }
  end

  defp from_stripe_response({:ok, %{"id" => id, "status" => "succeeded"}}) do
    {:ok, %{provider_id: id, status: :paid}}
  end

  defp from_stripe_response({:error, %{"code" => code}}) do
    {:error, {:provider_rejected, code}}
  end
end
```

```elixir
defmodule MyApp.Storage do
  @callback put(path :: String.t(), body :: iodata()) :: :ok | {:error, term()}
  @callback get(path :: String.t()) :: {:ok, binary()} | {:error, term()}
end

defmodule MyApp.Storage.S3 do
  @behaviour MyApp.Storage

  @impl true
  def put(path, body), do: # translate to S3 request

  @impl true
  def get(path), do: # translate from S3 response
end
```

## DON'T

```elixir
# Why wrong: the core consumes Stripe's response model directly.
def complete_order(order, token) do
  case Stripe.PaymentIntent.create(%{amount: order.total_cents, source: token}) do
    {:ok, %{"id" => stripe_id, "status" => "succeeded"}} ->
      finalize(order, stripe_id)

    {:error, %{"code" => "card_declined"}} ->
      {:error, {:stripe_failed, "card_declined"}}
  end
end
```

```elixir
# Why wrong: a single Postgres implementation is wrapped in a fake swappable port.
defmodule MyApp.UsersPort do
  @callback get_user(id :: Ecto.UUID.t()) :: {:ok, User.t()} | {:error, term()}
end
```
