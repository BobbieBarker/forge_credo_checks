---
type: adr
id: 9
title: Structural Dispatch Over Imperative Branching
status: accepted
date: 2026-05-06
tags: [elixir, control-flow, pattern-matching, dispatch, idioms]
description: "Express dispatch using Elixir's structural constructs (multi-clause heads, guards, with, pipelines, cond) instead of if/case inside function bodies. Reserve if/unless for inline value selection within an expression."
---
# ADR-009: Structural Dispatch Over Imperative Branching

The body of a function is for computation, not for selecting which computation to perform. Use multi-clause heads, guards, `with`, pipelines, or `cond` for dispatch.

## Context

- `if`/`case`/`cond` ladders inside function bodies hide the dispatch surface from the function head, prevent pattern matching from binding subterms, and remove information from compiler reachability checks and Dialyzer flow analysis.
- Multi-clause heads expose the dispatch surface at the head; callers and tooling see every variant a function handles without reading the body.
- Each Elixir construct fits a specific shape of discriminator. They are not interchangeable.
- Inline `if`/`unless` for value selection inside a larger expression (the language's ternary) is correct; it is not the construct this ADR forbids.

## Consequence

- Multi-line `if`/`else` blocks at the top of a function body do not appear. They have become multi-clause heads, guards, `with`, pipelines, or `cond`.
- Adding a variant means adding a clause, not editing a body.
- Inline `if`/`unless` is fine for value selection inside an expression. The diagnostic: would removing the `if` and pulling its branches out as sibling clauses make the function structurally cleaner? If yes, this ADR forbids it.

## Rules

- Match argument shape in the function head: when behavior depends on the shape of an argument, on a tagged variant, or on a literal atom value, write one clause per case.
- Express predicate dispatch with guards: numeric ranges, type tags via `is_*` BIFs, simple computed checks go in `when` clauses on the function head.
- Compose fallible steps with `with`: when a sequence of operations each return `{:ok, _} | {:error, _}`, bind each with `<-` (see ADR-014).
- Thread sequential transformations through a `|>` pipeline; use `tap/2` for in-chain side effects, `then/2` to adapt shapes (see ADR-012).
- Use `cond` for ordered predicates with no single discriminating argument (predicates over multiple arguments or computed values). Make the `true ->` catch-all explicit.
- Use `if`/`unless` only for inline value selection inside a larger expression (string interpolation, struct field, list element, function argument).

## DO

```elixir
# lib/my_app/inventory.ex - multi-clause head dispatches on event kind
defmodule MyApp.Inventory do
  def handle_event(%{kind: :create, sku: sku} = event, state),
    do: create(sku, event, state)

  def handle_event(%{kind: :update, sku: sku} = event, state),
    do: update(sku, event, state)

  def handle_event(%{kind: :delete, sku: sku}, state),
    do: delete(sku, state)
end
```

```elixir
# lib/my_app/scoring.ex - guards express predicate dispatch
defmodule MyApp.Scoring do
  def classify(score) when is_integer(score) and score >= 90, do: :a
  def classify(score) when is_integer(score) and score >= 80, do: :b
  def classify(score) when is_integer(score) and score >= 70, do: :c
  def classify(score) when is_integer(score), do: :f
end
```

```elixir
# lib/my_app/severity.ex - cond for ordered predicates over multiple fields
defmodule MyApp.Severity do
  def of(event) do
    cond do
      event.error_count > 100 -> :critical
      event.error_count > 10 -> :high
      event.duration_ms > 5_000 -> :medium
      true -> :low
    end
  end
end
```

```elixir
# lib/my_app/notifications.ex - inline if for value selection (correct usage)
defmodule MyApp.Notifications do
  def greeting(name) do
    "Hi #{if name, do: name, else: "stranger"}"
  end

  def role_label(%{admin?: admin?, name: name}) do
    %{label: name, badge: if(admin?, do: "★", else: "")}
  end
end
```

## DON'T

```elixir
# Why wrong: nested if ladder hides the dispatch surface from the function
# head. Pattern matching cannot bind subterms. New variants require body
# edits instead of new clauses.
defmodule MyApp.Inventory do
  def handle_event(event, state) do
    if event.kind == :create do
      create(event.sku, event, state)
    else
      if event.kind == :update do
        update(event.sku, event, state)
      else
        delete(event.sku, state)
      end
    end
  end
end
```

```elixir
# Why wrong: the conditional is the entire body, branches are
# statement-shaped calls. The function head is the right place to dispatch
# on payload.kind.
def send(payload) do
  if payload.kind == :digest do
    Mailer.deliver(:digest, payload)
  else
    Mailer.deliver(:single, payload)
  end
end
```

## Applies To
- `lib/**/*.ex`
- `apps/*/lib/**/*.ex`
