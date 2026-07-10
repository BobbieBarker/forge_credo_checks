---
type: adr
id: 1
title: Structured Error Systems
status: accepted
date: 2026-05-08
tags: [elixir, errors, error-message, result-tuples]
description: "Every fallible function returns `{:ok, value} | {:error, %ErrorMessage{}}`. Construct errors via `ErrorMessage.not_found/2`, `unauthorized/2`, etc. Use the closed set of HTTP-derived code atoms. Keep user-facing text in `message` and debugging context in `details`."
---
# 001: Structured Error Systems

All errors use `%ErrorMessage{}` structs with `code`, `message`, and `details` fields. No bare strings, no bare atoms.

## Context

- Bare string errors (`{:error, "not found"}`) force callers into fragile string matching.
- Bare atom errors (`:not_found`) carry no human-readable context for API responses.
- Mixed error shapes across modules force every caller to handle multiple formats.
- Errors are structured data with a consistent shape for reliable pattern matching, fallback-controller dispatch, and structured logging.

## Consequence

- Every function that can fail returns `{:ok, value} | {:error, %ErrorMessage{}}`.
- You construct errors through `ErrorMessage.not_found/2`, `ErrorMessage.unauthorized/2`, `ErrorMessage.conflict/2`, etc., not by hand-building the struct.
- Pattern matching on errors always matches on `%ErrorMessage{code: atom}`, never on strings or bare atoms.
- At system boundaries (controllers, workers, channels), unexpected crashes get wrapped in `%ErrorMessage{}`.

## Rules

- Every function that can fail returns `{:ok, value} | {:error, %ErrorMessage{}}`. Use `ErrorMessage.t_res(type)` for return-type specs and `ErrorMessage.t_ok_res()` when the success path is bare `:ok`.
- No bare string errors. No bare atom errors. `%ErrorMessage{}` only.
- The `code` field uses HTTP-derived atoms from the closed set: `:not_found`, `:unauthorized`, `:unprocessable_entity`, `:internal_server_error`, `:conflict`, `:forbidden`, `:bad_request`, `:too_many_requests`. Do not invent custom codes.
- Construct errors via the `ErrorMessage` constructor functions (`ErrorMessage.not_found/2`), not by hand-building the struct.
- The `message` field is human-readable: suitable for API responses, dashboard error displays, email notifications.
- The `details` field carries debugging context (IDs, params, constraints, third-party error payloads). Logged, not always exposed.
- Unexpected errors (crashes, timeouts) get wrapped in `%ErrorMessage{}` at system boundaries. Internal code lets them crash per OTP.

## DO

```elixir
# apps/qr_king_pg/lib/qr_king_pg/codes.ex
# Example from QRKing — adapt paths to your project
@spec find(map()) :: ErrorMessage.t_res(Code.t())
def find(%{short_code: code}) do
  case Actions.find(Code, %{short_code: code}) do
    {:ok, code} -> {:ok, code}
    {:error, _} -> {:error, ErrorMessage.not_found("QR code not found", %{short_code: code})}
  end
end
```

```elixir
# apps/qr_king_web/lib/qr_king_web/controllers/fallback_controller.ex
# Example from QRKing — adapt paths to your project
def call(conn, {:error, %ErrorMessage{code: :not_found} = error}) do
  conn
  |> put_status(:not_found)
  |> put_view(json: ErrorJSON)
  |> render(:error, error: error)
end
```

## DON'T

```elixir
# Why wrong: bare string. Callers cannot pattern match on the kind of failure.
def find(%{short_code: code}) do
  case Actions.find(Code, %{short_code: code}) do
    {:ok, code} -> {:ok, code}
    {:error, _} -> {:error, "QR code not found"}
  end
end
```

```elixir
# Why wrong: bare atom. No message for users, no debugging details.
def find(%{short_code: code}) do
  case Actions.find(Code, %{short_code: code}) do
    {:ok, code} -> {:ok, code}
    {:error, _} -> {:error, :not_found}
  end
end
```

```elixir
# Why wrong: hand-built struct can drift from canonical shape; custom code
# breaks fallback-controller dispatch.
{:error, %ErrorMessage{code: :user_not_found, message: "User not found", details: %{}}}
```

## Applies To
- `lib/**/*.ex`
- `apps/*/lib/**/*.ex`
