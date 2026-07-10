---
type: adr
id: 15
title: Use Repo.transact for Database Transactions
status: accepted
date: 2026-05-08
tags: [elixir, ecto, transactions, ecto-shorts, error-handling]
description: "Use Repo.transact/1 for all database transactions: it auto-commits on {:ok, _} and auto-rolls back on {:error, _}, removing manual Repo.rollback/1 calls and else clauses from transaction bodies. Repo.transaction/1,2 is reserved for the rare case where auto-introspection genuinely does not fit."
---
# ADR-015: Use Repo.transact for Database Transactions

Use `Repo.transact/1` for every database transaction. Do not call `Repo.transaction/1,2` directly.

## Context

- `Repo.transaction/1,2` does not introspect the return value of the function it wraps. The caller must call `Repo.rollback/1` explicitly on every error path.
- The asymmetry produces a class of bugs: forgetting `else` returns `{:ok, {:error, reason}}` from the function, Ecto reads the outer `{:ok, _}` and commits, the inner work's failure is silently swallowed.
- `Repo.transact/1` (provided by `EctoShorts`, or rolled at the project level) inspects the return value: `{:ok, _}` commits, `{:error, _}` rolls back. The contract is symmetric with the `with`/`<-` semantic from ADR-014.

## Consequence

- Database transactions use `Repo.transact/1`. `Repo.transaction/1,2` direct calls do not appear in domain code.
- `with` chains inside `Repo.transact` are bare per ADR-014 Rule 2. Failures emerge from helpers as `{:error, _}` and propagate through the wrapper unchanged.
- Functions called inside `Repo.transact` return `{:ok, _}` or `{:error, _}`. Bare values are not threaded into the wrapper.

## Rules

- Wrap the transaction body in `Repo.transact/1`. The body returns `{:ok, value}` or `{:error, reason}`; the wrapper auto-commits or auto-rolls back accordingly.
- The `with` chain inside is bare (no `else`).
- New projects either depend on EctoShorts (which provides `Repo.transact`) or include a small wrapper module that does the introspection. There is no third option that preserves the auto-introspection contract.

## DO

```elixir
# lib/my_app/accounts.ex - Repo.transact + bare with
defmodule MyApp.Accounts do
  alias MyApp.Repo

  def register_user(email) do
    org_name = email |> String.split("@") |> List.last() |> default_org_name()

    Repo.transact(fn ->
      with {:ok, org} <- Organizations.create(%{name: org_name}),
           {:ok, user} <- create_user(%{email: email, organization_id: org.id}) do
        {:ok, user}
      end
    end)
  end
end
```

## DON'T

```elixir
# Why wrong: Repo.transaction/1 with manual rollback in else. Re-introduces
# the ADR-014 anti-pattern. Forgetting else returns {:ok, {:error, reason}}
# from the function; Ecto sees the outer {:ok, _} and commits, swallowing
# the inner failure.
defmodule MyApp.Accounts do
  alias MyApp.Repo

  def register_user(email) do
    org_name = email |> String.split("@") |> List.last() |> default_org_name()

    Repo.transaction(fn ->
      with {:ok, org} <- Organizations.create(%{name: org_name}),
           {:ok, user} <- create_user(%{email: email, organization_id: org.id}) do
        user
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end
end
```

## Applies To
- `lib/**/*.ex`
- `apps/*/lib/**/*.ex`
