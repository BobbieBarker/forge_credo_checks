---
type: adr
id: 20
title: HTTP Boundary Testing
status: accepted
date: 2026-05-08
tags: [elixir, testing, http, req-test, boundaries]
description: "Tag every outbound HTTP request with a service identifier from a closed set. Pipe responses through a shared handler that normalizes errors to %ErrorMessage{}. Test at the HTTP boundary with Req.Test, never Mox at the adapter level. Stubs MUST assert on the request body, not just return canned responses."
---
# 020: HTTP Boundary Testing

Tag every outbound HTTP request with a closed-set service identifier. Pipe responses through a shared handler. Test at the HTTP boundary with `Req.Test` (not Mox at the adapter level). Test stubs assert on the request, not just the response.

## Context

- Mox at the adapter level skips request construction, parameter encoding, and response parsing: that is where most bugs in API clients live.
- Tests that only check the response shape pass whether the application sent the right query, the wrong query, or no query at all (the Symphony Linear `nodes` incident).
- Per-service `finch_private` tags drop per-service metrics out of Finch's existing telemetry events for free.
- A shared response handler normalizes errors to `%ErrorMessage{}` at the boundary, so the rest of the codebase sees canonical error codes.

## Consequence

- Every Req call carries `finch_private: %{service: :name}` with `:name` from a closed atom enumeration (`:stripe`, `:linear`, `:cloudflare`, ...).
- Every Req result pipes through `SharedUtils.HTTP.handle_response/2` (or the project's equivalent).
- Adapter tests stub `MyApp.HTTPClient` via `Req.Test` and inspect the actual request the adapter constructs.
- Tests using `Req.Test.expect/2` pair with `verify_on_exit!` so missing calls fail.

## Rules

- Tag every outbound request with `finch_private: %{service: atom_from_closed_set}`. Service identifiers come from a known list of services the application talks to; never from URLs or hosts.
- Pipe every response through `SharedUtils.HTTP.handle_response(result, :service)` (or the project's equivalent). The handler normalizes successful responses to `{:ok, body}` and 4xx/5xx/transport errors to `{:error, %ErrorMessage{}}`.
- Test stubs MUST inspect `conn.method`, `conn.request_path`, request headers, and the request body (`Plug.Conn.read_body/1`). A test that returns a canned response without checking what was sent is testing nothing.
- Use `Req.Test.stub/2` in `setup` blocks for default responses any test in the file can rely on. Use `Req.Test.expect/2` in test bodies for ordered/counted assertions about specific calls.
- Pair `Req.Test.expect/2` with `setup :verify_on_exit!` so unconsumed expectations fail the test.
- Mox is reserved for in-process behaviours (caches, clocks, feature-flag stores). For HTTP-backed adapters, Req.Test is the right tool.

## DO

```elixir
# apps/qr_king_payments/lib/qr_king_payments/stripe_adapter.ex
# Example from QRKing — adapt paths to your project
def charge(amount, token) do
  Req.post(
    base_url() <> "/charges",
    body: %{amount: amount, source: token},
    finch_private: %{service: :stripe}
  )
  |> SharedUtils.HTTP.handle_response(:stripe)
end
```

```elixir
# apps/qr_king_payments/test/.../stripe_adapter_test.exs
# Example from QRKing — adapt paths to your project
defmodule QRKingPayments.StripeAdapterTest do
  use ExUnit.Case, async: true
  setup :verify_on_exit!

  test "charge/2 posts the right body and parses the response" do
    Req.Test.expect(QRKingPayments.HTTPClient, fn conn ->
      assert conn.method == "POST"
      assert conn.request_path == "/v1/charges"
      assert {:ok, body, _} = Plug.Conn.read_body(conn)
      assert URI.decode_query(body) == %{"amount" => "1000", "source" => "tok_visa"}

      Req.Test.json(conn, %{"id" => "ch_abc", "status" => "succeeded"})
    end)

    assert {:ok, %{"id" => "ch_abc"}} = StripeAdapter.charge(1000, "tok_visa")
  end

  test "charge/2 normalizes 422 to %ErrorMessage{code: :bad_request}" do
    Req.Test.expect(QRKingPayments.HTTPClient, fn conn ->
      conn
      |> Plug.Conn.put_status(422)
      |> Req.Test.json(%{"error" => %{"code" => "card_declined", "message" => "Declined"}})
    end)

    assert {:error, %ErrorMessage{code: :bad_request, details: %{service: :stripe, status: 422}}} =
             StripeAdapter.charge(1000, "tok_visa")
  end
end
```

## DON'T

```elixir
# Why wrong: Mox at adapter level skips request construction and parsing.
# A bug in how the adapter builds or parses HTTP is invisible to this test.
expect(QRKingPayments.MockAdapter, :charge, fn _amount, _token ->
  {:ok, %{"id" => "ch_abc"}}
end)

assert {:ok, _} = Checkout.complete_order(@order, "tok_visa")
```

```elixir
# Why wrong: stub returns canned response with no assertion on the request.
# The test passes whether the adapter sends "POST /v1/charges" with the right
# body or sends "GET /v1/refunds" with empty body.
Req.Test.stub(QRKingPayments.HTTPClient, fn conn ->
  Req.Test.json(conn, %{"id" => "ch_abc", "status" => "succeeded"})
end)

assert {:ok, _} = StripeAdapter.charge(1000, "tok_visa")
```

```elixir
# Why wrong: missing finch_private tag, no shared response handler.
# No per-service telemetry, no canonical error normalization.
Req.post(base_url() <> "/charges", body: %{amount: 1000, source: token})
|> case do
  {:ok, %{status: 200, body: body}} -> {:ok, body}
  _ -> {:error, "stripe failed"}
end
```

## Applies To
- `apps/*/lib/**/*adapter*.ex`
- `apps/*/test/**/*adapter*_test.exs`
- `lib/**/*adapter*.ex`
- `test/**/*adapter*_test.exs`
