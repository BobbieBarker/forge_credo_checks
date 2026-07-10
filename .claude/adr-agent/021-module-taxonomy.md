---
type: adr
id: 21
title: Module Taxonomy
status: accepted
date: 2026-05-08
tags: [forge, architecture, modules, taxonomy]
description: "Every module is one of five categories: Context (public API for a domain), Service (orchestrates across contexts), Port (wraps one external service per ADR 002), SDK/Library (pure logic, no supervision tree), Shared Utility (zero domain knowledge). Dependencies flow downward through the categories. Shared Utility imports nothing domain-specific."
---
# 021: Module Taxonomy

Every module belongs to one of five categories with a fixed responsibility, dependency direction, and testing strategy. The category is identifiable from the file path.

## Context

- Without a taxonomy, modules accumulate concerns: the same `MyApp.Notifications` could be a context, service, port, library, or shared utility.
- Categories enforce dependency direction by build-system convention plus reviewer enforcement.
- Each category has a different test strategy: contexts test through the public API with DataCase; services test orchestration with stubbed ports; ports test the HTTP boundary with Req.Test; libraries test in isolation; shared utilities test without setup.

## Consequence

- Every module's category is identifiable from its file path.
- Dependencies flow downward through the categories. Web depends on services and contexts; services depend on contexts and ports; contexts depend on schemas and shared utilities; nothing in shared_utils imports anything domain-specific.
- Tests follow the category. The right test type for a module is the one matching its category.
- Shared utilities are extractable as Hex packages without dragging domain code along.

## Rules

- **Context modules** are the public API for one domain. Live in the database app (`MyAppPG.Users`). Depend on schemas, EctoShorts.Actions, Repo. Tested through the public API with DataCase.
- **Service modules** orchestrate across multiple contexts. Live in the web app or a dedicated service app. Depend on multiple contexts and ports. Never depend on the web layer (controllers, LiveViews, plugs).
- **Port modules** wrap exactly one external service per ADR 002. Live in a dedicated port app (`my_app_payments`). Vendor types do not escape the port. Tested at the HTTP boundary with Req.Test (per ADR 020).
- **SDK / Library modules** carry pure domain logic with no supervision tree. Live in library apps (`my_app_jobs`, `my_app_gs1`). Deployed by consuming apps; do not run on their own.
- **Shared Utility modules** have ZERO business domain knowledge. Live in `shared_utils`. Audit rule: would I publish this as a Hex package? If no, it does not belong here.
- Dependencies flow downward through the categories. Cross-direction imports (a context calling a service, a port importing the web layer) are architectural debt.

## DO

```elixir
# Context: public API for a domain
defmodule MyAppPG.Users do
  alias MyAppPG.Users.User
  alias EctoShorts.Actions

  def find_user(params), do: Actions.find(User, params)
  def list_users_for_org(org_id), do: ...
end

# Service: orchestrates across contexts and ports
defmodule MyApp.Checkout do
  alias MyAppPG.{Orders, Inventory}
  alias MyAppPayments

  def complete_order(order_id, token) do
    with {:ok, order} <- Orders.find_order(%{id: order_id}),
         :ok <- Inventory.reserve(order),
         {:ok, charge} <- MyAppPayments.charge(order.total, token) do
      Orders.mark_completed(order, charge.id)
    end
  end
end

# Shared utility: zero domain knowledge
defmodule SharedUtils.HTTP do
  def handle_response({:ok, %{status: status, body: body}}, _service) when status in 200..299, do: {:ok, body}
  def handle_response(_, service), do: {:error, ErrorMessage.internal_server_error("#{service} failed", %{})}
end
```

## DON'T

```elixir
# Why wrong: controller doing service work (orchestrating four contexts and a port).
# The orchestration cannot be reused from a LiveView, worker, or mix task.
def create(conn, %{"order_id" => id, "token" => token}) do
  with {:ok, order} <- Orders.find_order(%{id: id}),
       :ok <- Inventory.reserve(order),
       {:ok, charge} <- MyAppPayments.charge(order.total, token),
       {:ok, completed} <- Orders.mark_completed(order, charge.id) do
    Notifications.send_order_confirmation(completed)
    json(conn, %{order_id: completed.id})
  end
end
```

```elixir
# Why wrong: shared_utils with domain knowledge (imports Order schema).
defmodule SharedUtils.OrderHelpers do
  alias MyAppPG.Orders.Order

  def order_total_with_tax(%Order{} = order, tax_rate) do
    Enum.sum(Enum.map(order.line_items, & &1.amount)) * (1 + tax_rate)
  end
end
```

## Applies To
- All `.ex` files
- `lib/**/*.ex`
- `apps/*/lib/**/*.ex`
