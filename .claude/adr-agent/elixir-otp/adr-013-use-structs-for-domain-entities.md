---
type: adr
id: 13
title: Use Structs for Domain Entities
status: accepted
date: 2026-05-08
tags: [elixir, structs, types, dialyzer, jason, serialization]
description: "Define every domain entity as a struct with @type t for Dialyzer flow, @enforce_keys for required fields, and @derive {Jason.Encoder, only: [...]} with an explicit field list to gate JSON exposure. Plain maps are reserved for genuinely ad-hoc data."
---
# ADR-013: Use Structs for Domain Entities

Domain entities are structs with `@type t`, `@enforce_keys`, and an explicit `@derive Jason.Encoder` field list. Plain maps are reserved for genuinely ad-hoc data.

## Context

- Plain maps in Elixir are flexible but undisciplined: any caller constructs one with any keys, missing required keys produce no error, shapes mutate silently across modules.
- Structs solve those problems at compile time: each module declares its fields, every instance is tagged with the struct name, and the shape is fixed.
- Three discipline points around structs are easy to forget and produce real bugs when missed: declaring `@type t` for Dialyzer, enforcing required keys at construction, and gating JSON encoding to an explicit field list.

## Consequence

- Domain entities have a Dialyzer-tracked shape, fail fast on construction when required fields are missing, and have explicit JSON exposure surfaces.
- A new field added to a struct does not silently leak into API responses; it requires an `:only`-list edit gated by code review.
- Plain maps stay reserved for unstructured input, dynamic config, intermediate computation that has no enduring shape.

## Rules

- Add `@type t :: %__MODULE__{}` to every struct module, listing each field with its type. Optional fields include `nil` in the type union.
- Use `@enforce_keys [:field1, :field2]` for fields that must be present at construction. Fields with default values stay out of `@enforce_keys`.
- The required fields in `@enforce_keys` should match the non-nullable fields in `@type t` (the ones whose type does not include `| nil`).
- Use `@derive {Jason.Encoder, only: [...]}` with an explicit field list. Do not derive without specifying. Use `:except` only when the omit-list is genuinely shorter and stable across additions.
- Function heads that dispatch on struct type pattern-match the struct name (per ADR-009 Rule 1), not on individual map keys.

## DO

```elixir
# lib/my_app/geo/location.ex - all three discipline points
defmodule MyApp.Geo.Location do
  @enforce_keys [:country_code]

  defstruct [:country_code, :region, :city, latitude: nil, longitude: nil]

  @type t :: %__MODULE__{
          country_code: String.t(),
          region: String.t() | nil,
          city: String.t() | nil,
          latitude: float() | nil,
          longitude: float() | nil
        }
end

# Usage:
%MyApp.Geo.Location{country_code: "US"}                # OK
%MyApp.Geo.Location{country_code: "US", region: "CA"}  # OK
%MyApp.Geo.Location{region: "CA"}                      # raises ArgumentError
```

```elixir
# lib/my_app/users/user.ex - explicit :only list gates exposure
defmodule MyApp.Users.User do
  @enforce_keys [:id, :email]

  @derive {Jason.Encoder, only: [:id, :email, :name, :created_at]}

  defstruct [
    :id,
    :email,
    :name,
    :password_hash,
    :failed_login_count,
    :created_at,
    :updated_at
  ]
end
```

## DON'T

```elixir
# Why wrong: no @type t. Dialyzer cannot flow field types through accesses.
# Specs that take a %MyApp.Geo.Location{} get only "this is a struct of
# this module"; field types are opaque to flow analysis.
defmodule MyApp.Geo.Location do
  defstruct [:country_code, :region, :city, latitude: nil, longitude: nil]
end
```

```elixir
# Why wrong: no @enforce_keys. Every field defaults to nil if not provided
# and the struct constructs successfully even when required fields are
# missing. The bug surfaces later when code reads loc.country_code and
# gets nil where a String.t() was expected.
defmodule MyApp.Geo.Location do
  defstruct [:country_code, :region, :city, latitude: nil, longitude: nil]
end

%MyApp.Geo.Location{region: "CA"}  # silently constructs with country_code: nil
```

```elixir
# Why wrong: @derive Jason.Encoder without :only encodes every field. A
# new field (password_hash, internal counter, audit timestamp) is silently
# included in API responses when added to the struct.
defmodule MyApp.Users.User do
  @enforce_keys [:id, :email]

  @derive Jason.Encoder

  defstruct [
    :id,
    :email,
    :name,
    :password_hash,
    :failed_login_count,
    :created_at,
    :updated_at
  ]
end
```

## Applies To
- `lib/**/*.ex`
- `apps/*/lib/**/*.ex`
