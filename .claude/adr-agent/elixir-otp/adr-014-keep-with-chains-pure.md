---
type: adr
id: 14
title: Keep `with` Chains Pure
status: accepted
date: 2026-05-08
tags: [elixir, control-flow, with, error-handling, fallible-chains]
description: "Inside a `with` chain, every line uses `<-` (no plain `=` bindings, which smuggle infallible work into the chain shape and don't participate in fall-through). Avoid `else` clauses; normalize return shapes in the called functions. Reach for `with` only when two or more fallible steps need to compose."
---
# ADR-014: Keep `with` Chains Pure

A `with` chain contains only `<-` steps that participate in fall-through, returns failures unchanged, and is reserved for sequences where at least two fallible steps depend on each other.

## Context

- `with` exists to chain operations where each step can fail. The `<-` arrow performs pattern-match-or-abort: a successful match binds and continues; a non-match aborts and returns the non-matched value as the result of the `with`.
- Plain `=` bindings inside the chain are not pattern-match-or-abort. They smuggle infallible work into the chain shape but do not participate in the fall-through control flow the macro exists to provide.
- An `else` block flattens every step's failure into a single block, obscuring which step produced the error. The fix is to make each called function return a fully-formed error shape so the bare `with` can let mismatches fall through unchanged.
- A `with` containing exactly one `<-` is overkill: a single fallible step is `case`. Pure transformations belong in pipelines, not `with`.

## Consequence

- `with` chains contain only `<-` steps. A line with `=` is a refactor signal: extract a composing helper or move the binding into the `do` block.
- `else` clauses are absent from almost every `with` in the codebase. Error normalization happens in the called functions.
- A bare `with` falls through cleanly to whatever non-match the first failing step produced. Callers receive that shape unchanged.

## Rules

- Every step in a `with` chain uses `<-`, never plain `=`. A `=` line is a misuse: extract a composing helper that returns the bundled result via `<-`, or move the binding into the `do` block where plain `=` is normal Elixir code.
- Avoid `else` clauses. Normalize return shapes in the called functions so each one emits the canonical error shape directly.
- Reach for `with` only when two or more fallible steps need to compose. A single fallible step is a `case`. A pure-data transformation chain is a pipeline.
- The only acceptable `else` is when called functions genuinely return structurally-incompatible error shapes you cannot fix at the source. Even then, prefer wrapping the call in a small adapter that emits the canonical shape.

## DO

```elixir
# lib/my_app/cli.ex - composing helper bundles infallible + fallible work
defmodule MyApp.CLI do
  def parse(raw_argv) do
    with :ok <- verify(),
         {:ok, opts} <- parse_options(raw_argv) do
      run(opts)
    end
  end

  defp parse_options(raw_argv) do
    case raw_argv |> normalize_argv() |> OptionParser.parse(strict: @opts_spec) do
      {opts, [], []} ->
        {:ok, opts}

      {_opts, _argv, errs} ->
        {:error,
         %ErrorMessage{
           code: :unprocessable_entity,
           message: "Bad options",
           details: %{errors: errs}
         }}
    end
  end
end
```

```elixir
# lib/my_app/accounts.ex - normalize at the source, no else clause
defmodule MyApp.Accounts do
  def register(email) do
    with :ok <- validate_email_format(email),
         :ok <- validate_email_unique(email),
         {:ok, user} <- Users.insert(%{email: email}) do
      {:ok, user}
    end
  end

  defp validate_email_format(email) do
    if Regex.match?(@email_regex, email) do
      :ok
    else
      {:error, %ErrorMessage{code: :unprocessable_entity, message: "Invalid email format"}}
    end
  end

  defp validate_email_unique(email) do
    case Users.find(%{email: email}) do
      {:ok, _user} ->
        {:error, %ErrorMessage{code: :conflict, message: "Email already registered"}}

      {:error, %ErrorMessage{code: :not_found}} ->
        :ok
    end
  end
end
```

```elixir
# lib/my_app/users.ex - single fallible step is a pass-through, not a with
def find_active(id) do
  Users.find(%{id: id, archived_at: nil})
end
```

## DON'T

```elixir
# Why wrong: argv = normalize_argv(raw_argv) does no pattern-match-or-abort
# work. It is a local rebind smuggled into the chain so the next <- step
# has the argument it needs.
def parse(raw_argv) do
  with :ok <- verify(),
       argv = normalize_argv(raw_argv),
       {:ok, opts} <- parse_options(argv) do
    run(opts)
  end
end
```

```elixir
# Why wrong: error normalization lives in the else block. Reader must
# trace which step produced which raw shape, then trace why the else
# clause maps to that final form.
def register(email) do
  with :ok <- validate_email_format(email),
       :ok <- validate_email_unique(email),
       {:ok, user} <- Users.insert(%{email: email}) do
    {:ok, user}
  else
    {:error, :invalid_format} ->
      {:error, %ErrorMessage{code: :unprocessable_entity, message: "Invalid email format"}}

    {:error, :duplicate} ->
      {:error, %ErrorMessage{code: :conflict, message: "Email already registered"}}
  end
end
```

```elixir
# Why wrong: single-step with is a case wearing heavier syntax. The with
# adds no control flow because there is nothing to fall through to.
def find_active(id) do
  with {:ok, user} <- Users.find(%{id: id, archived_at: nil}) do
    {:ok, user}
  end
end
```

```elixir
# Why wrong: pure transformations forced into with by wrapping each step
# in {:ok, _} so the `<-` works. Adds infrastructure to express what is
# just a pipeline.
def serialize(filters) do
  with {:ok, rejected} <- {:ok, Enum.reject(filters, &match?({_, nil}, &1))},
       {:ok, mapped} <- {:ok, Enum.into(rejected, %{})} do
    {:ok, URI.encode_query(mapped)}
  end
end
```

## Applies To
- `lib/**/*.ex`
- `apps/*/lib/**/*.ex`
