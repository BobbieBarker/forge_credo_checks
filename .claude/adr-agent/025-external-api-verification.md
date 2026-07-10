---
type: adr
id: 25
title: External API Verification
status: accepted
date: 2026-05-08
tags: [elixir, api, verification, external-services, llm-pitfalls]
description: "Never write external API calls from memory. Read official docs before writing client code; for GraphQL, curl the query against the real API first. Test stubs MUST assert on the request, not just the response. Maintain at least one :integration test per external API. A warning that fires every time is a bug, not a transient issue."
---
# 025: External API Verification

Never write external API calls from memory or by extrapolation from neighboring APIs. Verify every endpoint, parameter, query syntax, and response shape against the actual documentation before writing the Elixir client.

## Context

- LLMs (and humans) confidently produce client code that uses the wrong endpoint, parameter names, or query syntax based on patterns from neighboring APIs (GitHub's `nodes(ids: ...)` against Linear, Stripe's `metadata` against Cloudflare).
- The bug compiles, passes tests that mock the response without checking the request, and fails silently in production: HTTP 400 every poll, the error path catches it, a fallback returns stale or empty data, the system "appears to work."
- The canonical Symphony incident: the Linear adapter shipped with `nodes(ids: $ids)` (a GitHub pattern) instead of Linear's `issues(filter: { id: { in: $ids } })`. HTTP 400 for weeks. Tests passed because they mocked the response. Discovered when stale claims consumed all dispatch slots.
- A warning that fires every time, or a "graceful fallback" that always fires, is signalling a permanent failure that the error path is masking.

## Consequence

- Before writing any external API call, you'll fetch the official docs via `WebFetch` or `WebSearch`.
- For GraphQL APIs, you'll run the query via curl against the real API before writing the Elixir client.
- Test stubs will assert on the actual request the application sent (method, path, body, headers), not just return canned responses.
- Each external API adapter has at least one `@tag :integration` test that hits the real API. CI excludes them; they run manually before merging adapter changes.
- Persistent warnings get investigated immediately, not normalized into the log baseline.

## Rules

- Read the official API documentation before writing client code. Do not extrapolate from neighboring APIs.
- For GraphQL APIs, run the query manually via curl against the real API before writing the Elixir client. Paste the verifying curl command as a comment near the query definition.
- Test stubs MUST inspect `conn.method`, `conn.request_path`, request headers, and the request body. A test that returns a canned response without checking what was sent is testing nothing.
- Each external API adapter has at least one test marked `@tag :integration` that hits the real API. Excluded from CI; run manually before merging adapter changes.
- A warning that fires every time is a bug, not a transient issue. Investigate immediately. The same applies to error handlers that always run: the fallback is masking a bug, not handling a normal case.
- Existing client code in the project is the canonical pattern reference. Before writing a new client, read the existing one for this API.

## DO

```bash
# Verify the query against the real API before writing Elixir:
curl -s -X POST https://api.linear.app/graphql \
  -H "Authorization: $LINEAR_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"query":"query($ids: [ID!]) { issues(filter: { id: { in: $ids } }) { nodes { id state { name } } } }", "variables": {"ids": ["abc"]}}'
```

```elixir
# Then write the client matching the verified query.
# The verifying curl is preserved as a comment.
defmodule MyApp.Linear.Client do
  # Verified 2026-05-08:
  # curl -s -X POST https://api.linear.app/graphql -H "Authorization: $LINEAR_API_KEY" \
  #   -d '{"query":"query($ids: [ID!]) { issues(filter: { id: { in: $ids } }) { nodes { id state { name } } } }"}'
  defp issue_states_query do
    """
    query($ids: [ID!]) {
      issues(filter: { id: { in: $ids } }) {
        nodes { id state { name } }
      }
    }
    """
  end
end
```

```elixir
# Test asserts on the request, not just the response:
test "fetch_issue_states/1 sends the right GraphQL query" do
  Req.Test.expect(MyApp.HTTPClient, fn conn ->
    {:ok, body, _} = Plug.Conn.read_body(conn)
    decoded = Jason.decode!(body)

    assert decoded["query"] =~ "issues(filter: { id: { in: $ids } })"
    assert decoded["variables"] == %{"ids" => ["abc"]}

    Req.Test.json(conn, %{"data" => %{"issues" => %{"nodes" => [%{"id" => "abc", "state" => %{"name" => "Done"}}]}}})
  end)

  assert {:ok, [%{id: "abc", state: "Done"}]} = LinearClient.fetch_issue_states(["abc"])
end
```

## DON'T

```elixir
# Why wrong: extrapolated from GitHub's GraphQL pattern. Linear has no
# `nodes` query. Returns HTTP 400 in production.
defp issue_states_query do
  """
  query($ids: [ID!]!) {
    nodes(ids: $ids) {
      ... on Issue { id state { name } }
    }
  }
  """
end
```

```elixir
# Why wrong: stub returns canned response without checking the request.
# The test passes whether the application sends the right query, the wrong
# query, or no query at all.
Req.Test.stub(MyApp.HTTPClient, fn conn ->
  Req.Test.json(conn, %{"data" => %{"issues" => %{"nodes" => [...]}}})
end)

assert {:ok, _} = LinearClient.fetch_issue_states(["abc"])
```

```elixir
# Why wrong: warning fires every time and the fallback always returns stale
# state. The "transient" framing masks a permanent bug.
def fetch do
  case do_fetch() do
    {:ok, data} ->
      {:ok, data}

    {:error, _} ->
      Logger.warning("Linear fetch failed, using cached state")
      {:ok, @stale_cached_state}
  end
end
```

## Applies To
- `lib/**/*client*.ex`
- `lib/**/*adapter*.ex`
- `apps/*/lib/**/*client*.ex`
- `apps/*/lib/**/*adapter*.ex`
- `test/**/*client*_test.exs`
- `test/**/*adapter*_test.exs`
