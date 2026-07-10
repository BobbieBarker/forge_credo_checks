---
type: adr
id: 4
title: Testing Pyramid
status: accepted
date: 2026-05-08
tags: [elixir, testing, testing-pyramid, exunit]
description: "Tests live in four layers: module public-API tests carry the bulk; HTTP boundary tests are thin; LiveView tests are full investment; Playwright E2E covers only critical user paths. Test through the public API. Don't test what you don't own. Don't assert on observability. Assert all side effects."
---
# 004: Testing Pyramid

Tests live in four layers, each at its right architectural boundary. Module public-API tests carry the bulk; HTTP boundary tests verify the wire; LiveView tests cover interaction flows; Playwright E2E covers only critical paths nothing else can.

## Context

- Lower-layer tests are cheap and reach edge cases higher layers cannot (DB constraint violations, malformed parser input, retry behavior).
- Higher-layer tests cost more but exercise integration paths (request shape, LiveView mount, multi-page flows).
- Mismatched layering produces brittle tests: E2E tests that should be unit tests break on every UI tweak; unit tests that mock too much pass while production breaks.
- Library and framework contracts are trusted; the application's tests assert on the application's code.

## Consequence

- Module public-API tests dominate the suite. They use DataCase, ExMachina, async: true.
- HTTP boundary tests are thin: status code, response shape, auth, error serialization. They do NOT re-test context behavior.
- LiveView tests are full: mount, events, navigation, real-time updates. LiveView tests are easy to write and catch real user-facing bugs.
- Playwright E2E is reserved for flows nothing else can verify (broken JS hooks, CSS hiding a button, multi-page sessions).
- Telemetry events and log output are NOT test-suite assertions.
- Every side effect (DB write, Oban enqueue, email, PubSub broadcast, cache write) is asserted.

## Rules

- Test through the module's public API. Do not promote `defp` to `@doc false def` for tests; do not use `:erlang` reflection.
- Awkward setup is a signal to reshape the API, not to expose internals.
- Library contracts are trusted: do not test that Oban retries on `{:error, _}`, that Ecto rolls back on `Repo.rollback/1`, or that Phoenix dispatches to a controller. Assert on YOUR code's contribution.
- Telemetry events, log output, and observability emissions are NOT test assertions. Tests do not call `:telemetry_test.attach_event_handlers/2`, do not grep log output, do not assert Sentry was called.
- Every side effect a function performs is asserted: DB rows via `Repo.get!/2`, Oban via `assert_enqueued/1`, email via `assert_email_sent/1`, PubSub via `assert_received/1`, cache writes via direct cache reads.
- Match test type to subject: controller tests assert status + response shape (not internal side effects); context tests assert return value + DB state; service tests assert orchestration result with stubbed ports; GenServer tests assert client API → state transitions.
- Use Req.Test for HTTP boundaries (per ADR 020). Use Mox for in-process behaviours that cannot be opts-injected (per ADR 007 Rule 5).
- `async: true` is the default; opt out only when shared global state demands it, with a comment naming why.

## DO

```elixir
# Module public-API test through the public function
test "register_user/1 hashes the password and stores the user" do
  email = Faker.Internet.email()

  assert {:ok, %User{email: ^email, password_hash: hash}} =
           Accounts.register_user(%{email: email, password: "secret"})

  refute hash == "secret"
  assert byte_size(hash) > 0
end
```

```elixir
# Asserts ALL side effects of publish_post/2
test "publish_post/2 inserts post, enqueues notifications, broadcasts" do
  user = insert(:user)
  follower = insert(:user)
  insert(:follow, user: follower, target: user)

  assert {:ok, %Post{id: post_id}} = Posts.publish_post(user, %{title: "Hello"})

  assert %Post{published: true} = Repo.get!(Post, post_id)
  assert_enqueued(worker: NotifyFollowersWorker, args: %{"post_id" => post_id})
  assert_received {:post_published, %Post{id: ^post_id}}
  assert_email_sent(to: follower.email, subject: "New post: Hello")
end
```

## DON'T

```elixir
# Why wrong: tests private function via @doc false promotion. Brittle.
test "hash_password/1 produces a bcrypt hash" do
  hash = Accounts.hash_password("hello")
  assert byte_size(hash) > 0
end
```

```elixir
# Why wrong: tests Oban's retry behavior, not the worker's logic.
test "Oban retries on {:error, _}" do
  enqueue_job(user.id)
  simulate_failure()
  assert_retry_count(2)
end
```

```elixir
# Why wrong: telemetry assertion couples test to instrumentation, not feature.
test "create_payment/1 emits the right telemetry event" do
  ref = :telemetry_test.attach_event_handlers(self(), [[:my_app, :payments, :charged]])
  Payments.create_payment(@valid_params)
  assert_receive {[:my_app, :payments, :charged], ^ref, _, _}
end
```

```elixir
# Why wrong: only asserts return value. Misses DB writes, Oban enqueues, emails.
test "publish_post/2 returns ok" do
  assert {:ok, %Post{}} = Posts.publish_post(@user, %{title: "Hello"})
end
```

## Applies To
- `test/**/*_test.exs`
- `apps/*/test/**/*_test.exs`
