---
type: adr
id: 3
title: Composable Queries
status: accepted
date: 2026-05-08
tags: [elixir, ecto, ecto-shorts, queries, schemas, contexts]
description: "Three-layer query architecture: EctoShorts.Actions for generic CRUD, schema modules for composable query fragments with named bindings, context modules for thin orchestration. Mutations use one function name with multi-clause heads. Schemas declare @required/@allowed and a single changeset/2 for create and update."
---
# 003: Composable Queries

Query architecture splits across three layers: `EctoShorts.Actions` handles generic CRUD with no custom code, schema modules export composable query fragments with named bindings, context modules orchestrate fragments and never contain inline query logic.

## Context

- Inline query logic in context modules accumulates over time and resists reuse across contexts.
- Schema-level fragments with named bindings compose in any order; positional bindings break under composition.
- `EctoShorts.Actions` lifts standard params-based filtering, error normalization to `%ErrorMessage{}`, and pagination into the library.
- Mutations have one public name per operation; multi-clause heads handle the struct-vs-find-params variants without exposing two function names.

## Consequence

- Context functions are pipes that compose schema fragments and end in `Actions.all/2`, `Actions.find/2`, etc.
- `Repo.*` calls in context modules are anti-pattern. Direct `from`, `where`, `join`, `select`, `subquery` macros in contexts are anti-pattern.
- Schema modules export `from/0,1` plus fragment functions, each adding one constraint with named bindings.
- Mutations are one function name with two clauses: a struct-arg clause and a find-params-map clause.

## Rules

- Use `EctoShorts.Actions.all/2`, `find/2`, `create/2`, `update/3`, `delete/1` for standard CRUD. Never call `Repo.all/1`, `Repo.one/2`, `Repo.insert/2`, `Repo.update/2`, or `Repo.delete/2` directly from a context module.
- Each schema exports `from(query \\ __MODULE__)` establishing a named binding (`as: :codes`). Fragment functions reference bindings by name, never positionally.
- Fragment functions default the query argument to `from()` so they compose left-to-right in pipes. Each fragment adds ONE constraint; never use `exclude(:where)` or other destructive operations.
- Context modules contain no `from`, `where`, `join`, `select`, `subquery` macros. They orchestrate fragments and call `Actions.*`.
- Mutation public APIs use one function name with multi-clause heads: one matching `%Schema{}`, one matching a find-params map.
- Schemas declare `@required` and `@allowed` module attributes for field lists, plus a single `changeset/2` that handles create and update (`cast/3` only touches fields present in params).

## DO

```elixir
# Schema with composable fragments
defmodule MyApp.Codes.Code do
  use Ecto.Schema
  import Ecto.Query

  schema "codes" do
    field :short, :string
    field :archived_at, :utc_datetime
    belongs_to :organization, MyApp.Organizations.Organization
    timestamps()
  end

  def from(query \\ __MODULE__),
    do: from(c in query, as: :codes)

  def by_organization(query \\ from(), org_id),
    do: where(query, [codes: c], c.organization_id == ^org_id)

  def active(query \\ from()),
    do: where(query, [codes: c], is_nil(c.archived_at))
end
```

```elixir
# Context: thin orchestration via Actions
defmodule MyApp.Codes do
  alias MyApp.Codes.Code
  alias EctoShorts.Actions

  def create_code(params), do: Actions.create(Code, params)
  def find_code(params), do: Actions.find(Code, params)

  def list_active_codes(org_id) do
    Code.from()
    |> Code.by_organization(org_id)
    |> Code.active()
    |> Actions.all()
  end
end
```

```elixir
# Mutation: one function name, two clause heads
def update_subscription(%Subscription{} = sub, params),
  do: Actions.update(Subscription, sub, params)

def update_subscription(find_params, params) when is_map(find_params),
  do: Actions.find_and_update(Subscription, find_params, params)
```

```elixir
# Single changeset/2 for create and update
defmodule MyApp.Users.User do
  @required [:email]
  @allowed @required ++ [:name, :phone]

  schema "users" do
    field :email, :string
    field :name, :string
    field :phone, :string
  end

  def create_changeset(params \\ %{}), do: changeset(%__MODULE__{}, params)

  def changeset(user, params) do
    user
    |> cast(params, @allowed)
    |> validate_required(@required)
    |> unique_constraint(:email)
  end
end
```

## DON'T

```elixir
# Why wrong: Repo direct calls in context, inline query DSL, no error normalization.
def list_active_codes(org_id) do
  Repo.all(
    from c in Code,
      where: c.organization_id == ^org_id and is_nil(c.archived_at)
  )
end
```

```elixir
# Why wrong: positional bindings break when fragments compose with joins added.
def by_organization(query \\ Code, org_id),
  do: where(query, [c], c.organization_id == ^org_id)
```

```elixir
# Why wrong: two function names for one operation; combinatorial growth.
def update_subscription_by_struct(sub, params), do: ...
def update_subscription_by_id(id, params), do: ...
```

```elixir
# Why wrong: separate create/update changesets duplicate field lists.
def create_changeset(user, params) do
  user |> cast(params, [:email, :name, :phone]) |> validate_required([:email])
end

def update_changeset(user, params) do
  user |> cast(params, [:name, :phone])
end
```

## Applies To
- `apps/*/lib/*/*.ex` (context modules)
- `apps/*/lib/*/*/*.ex` (schema modules)
- `lib/*/*.ex`
- `lib/*/*/*.ex`
