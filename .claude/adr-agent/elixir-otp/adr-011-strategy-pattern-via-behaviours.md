---
type: adr
id: 11
title: Strategy Pattern via Behaviours
status: accepted
date: 2026-05-08
tags: [elixir, design-patterns, behaviours, polymorphism, dependency-injection]
description: "Express runtime-pluggable internal algorithms as a behaviour contract plus N strategy modules conforming to it. Inject the strategy module via opts at call sites. Don't reach for Strategy when shape-based dispatch fits, and don't conflate it with Ports & Adapters at external-system boundaries."
---
# ADR-011: Strategy Pattern via Behaviours

When a client needs runtime-pluggable internal algorithms over the same input space, define a behaviour and implement each strategy as a module conforming to it. Inject the chosen strategy via opts.

## Context

- The Strategy pattern (Gang of Four) encapsulates a family of algorithms behind a common interface so client code uses any of them without knowing which is bound.
- In Elixir the natural mechanism is a `@behaviour`: one contract module declaring `@callback`s, plus N strategy modules each implementing those callbacks.
- Strategy is broadly useful (pricing variants, classifier strategies, scheduler policies). Authors often misframe it through the lens of one application (workflow orchestration), losing the general abstraction.
- Strategy is distinct from Ports & Adapters. Strategy is for internal algorithms over the same input space; P&A is for external-system boundaries with vendor types and serialization.

## Consequence

- Behaviour-based polymorphism is the default mechanism for runtime-pluggable internal algorithms. The contract is one declaration; each strategy is a module.
- Strategy modules are injected via opts at call sites (per ADR-007 Rule 5), not bound at compile time via `Application.compile_env`.
- Multi-clause function heads handle shape-driven dispatch (see ADR-009 Rule 1). Strategy is reserved for variants with distinct configuration, dependencies, or downstream coupling.
- External-system boundaries use Ports & Adapters, not Strategy.

## Rules

- Declare the contract as a behaviour and each strategy as a conforming module. The contract module uses `@callback`; each strategy declares `@behaviour Contract` and implements each callback with `@impl true`.
- Inject the strategy module via opts (or via a struct field) with a sensible production default. Tests pass a different module per test.
- Do not reach for Strategy when shape-based dispatch fits. If the only thing varying between variants is the function body and the body is small, multi-clause heads (ADR-009 Rule 1) are the lighter answer.
- Do not conflate Strategy with Ports & Adapters. Strategy is for internal interchangeable algorithms operating over the same input space. Ports & Adapters is for external-system boundaries (HTTP API, message broker, third-party SDK) with vendor types confined inside the adapter.

## DO

```elixir
# lib/my_app/pricing.ex - behaviour contract
defmodule MyApp.Pricing do
  @callback calculate(items :: [map()], context :: map()) :: Money.t()
end

# lib/my_app/pricing/standard.ex - one strategy
defmodule MyApp.Pricing.Standard do
  @behaviour MyApp.Pricing

  @impl true
  def calculate(items, _context) do
    items |> Enum.map(& &1.price) |> Enum.sum() |> Money.new()
  end
end

# lib/my_app/pricing/promotional.ex - another strategy with extra dependency
defmodule MyApp.Pricing.Promotional do
  @behaviour MyApp.Pricing

  @impl true
  def calculate(items, %{promo_code: code}) do
    base = items |> Enum.map(& &1.price) |> Enum.sum()
    discount = MyApp.Promos.discount_for(code)
    Money.new(base - discount)
  end
end
```

```elixir
# lib/my_app/checkout.ex - opts injection at call site
defmodule MyApp.Checkout do
  def total(items, context, opts \\ %{}) do
    pricing = Map.get(opts, :pricing, MyApp.Pricing.Standard)
    pricing.calculate(items, context)
  end
end

# test/my_app/checkout_test.exs - test passes its own strategy
test "checkout uses promotional pricing for code holders" do
  context = %{promo_code: "SAVE10"}
  assert %Money{amount: 90} =
           MyApp.Checkout.total(@items, context, %{pricing: MyApp.Pricing.Promotional})
end
```

```elixir
# lib/my_app/order_event.ex - shape-based dispatch via multi-clause head;
# Strategy would be overkill
defmodule MyApp.OrderEvent do
  def handle(%{kind: :placed, order_id: id}, state), do: mark_placed(state, id)

  def handle(%{kind: :shipped, order_id: id, tracking: t}, state),
    do: mark_shipped(state, id, t)

  def handle(%{kind: :cancelled, order_id: id}, state), do: mark_cancelled(state, id)
end
```

## DON'T

```elixir
# Why wrong: Strategy infrastructure (behaviour + 3 modules + router with
# strategies map) for a problem where the discriminator is the input's
# :kind tag and each branch is a function call. ADR-009 Rule 1 covers this.
defmodule MyApp.OrderEvent do
  @callback handle(event :: map(), state :: map()) :: map()
end

defmodule MyApp.OrderEventRouter do
  @strategies %{
    placed: MyApp.OrderEvent.Placed,
    shipped: MyApp.OrderEvent.Shipped,
    cancelled: MyApp.OrderEvent.Cancelled
  }

  def handle(%{kind: kind} = event, state) do
    strategy = Map.fetch!(@strategies, kind)
    strategy.handle(event, state)
  end
end
```

```elixir
# Why wrong: Stripe strategy with HTTP client calls leaking into a
# "strategy" module. External boundary needs Ports & Adapters with a
# serializer and explicit normalization to internal types.
defmodule MyApp.PaymentStrategy do
  @callback calculate(amount :: Money.t()) :: Money.t()
end

defmodule MyApp.PaymentStrategy.Stripe do
  @behaviour MyApp.PaymentStrategy

  @impl true
  def calculate(amount) do
    HTTPClient.post("/v1/charges", body: %{amount: amount})
  end
end
```

```elixir
# Why wrong: compile_env binds the strategy at compile time. Tests must
# mutate Application env to swap. Opts injection per ADR-007 Rule 5 keeps
# the choice at the call site.
defmodule MyApp.Checkout do
  @pricing Application.compile_env(:my_app, :pricing, MyApp.Pricing.Standard)

  def total(items, context), do: @pricing.calculate(items, context)
end
```

## Applies To
- `lib/**/*.ex`
- `apps/*/lib/**/*.ex`
