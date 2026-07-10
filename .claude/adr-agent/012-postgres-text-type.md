---
type: adr
id: 12
title: Postgres Text Type Convention
status: accepted
date: 2026-05-08
tags: [elixir, postgres, ecto, migrations, types]
description: "All Postgres string columns use `:text`. Use `:citext` for case-insensitive (emails, usernames). Length constraints belong in changesets via `validate_length/3`, not the database. Ecto schema field type stays `:string` regardless of column type; the two are independent."
---
# 012: Postgres Text Type Convention

All Postgres string columns use `:text`. `:citext` for case-insensitive columns (emails, usernames). Length constraints live in changesets, not the database.

## Context

- Ecto's `:string` migration type maps to `varchar(255)` in Postgres.
- The 255-byte cap is a MySQL-era artifact; Postgres treats `text`, `varchar(N)`, and `varchar` (no N) identically for storage, indexing, and sorting.
- Database length constraints require a migration (and a lock-acquiring `ALTER TABLE`) to change. Changeset constraints change in one schema-file edit and produce structured validation errors.
- The Ecto schema's field type is `:string` regardless of the column type; Ecto's `:string` is the in-memory Elixir representation (a binary), independent of the underlying column.

## Consequence

- New migrations use `:text` for variable-length strings and `:citext` for case-insensitive ones. `:string` does not appear as a migration type.
- Length caps come from `validate_length/3` in changesets.
- Email columns use `:citext`. Queries do not need to `LOWER(email)` for comparison; the unique index is case-insensitive at the column level.

## Rules

- Migration column type is `:text` for every variable-length string column.
- Migration column type is `:citext` for case-insensitive columns (emails, usernames).
- Length caps come from `validate_length(field, max: N)` in the changeset, not from `size: N` in the migration.
- Ecto schema field type stays `:string` for all text columns regardless of underlying database type.
- Existing `varchar(N)` columns can migrate to `:text` opportunistically; new columns do not perpetuate the pattern.

## DO

```elixir
# Migration
defmodule MyApp.Repo.Migrations.CreateUsers do
  use Ecto.Migration

  def change do
    create table(:users) do
      add :email, :citext, null: false
      add :name, :text, null: false
      add :bio, :text
      timestamps()
    end

    create unique_index(:users, [:email])
  end
end

# Schema
schema "users" do
  field :email, :string
  field :name, :string
  field :bio, :string
end

# Changeset
def changeset(user, params) do
  user
  |> cast(params, @allowed)
  |> validate_required(@required)
  |> validate_length(:name, max: 255)
  |> validate_length(:bio, max: 10_000)
  |> unique_constraint(:email)
end
```

## DON'T

```elixir
# Why wrong: :string maps to varchar(255). The 255-byte cap is arbitrary
# and changing it requires a migration that locks the table.
add :name, :string, size: 255
add :bio, :string, size: 10_000
```

## Applies To
- `priv/repo/migrations/*.exs`
- `apps/*/priv/repo/migrations/*.exs`
- `priv/*/migrations/*.exs`
