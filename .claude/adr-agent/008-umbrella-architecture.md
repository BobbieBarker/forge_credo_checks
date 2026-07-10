---
type: adr
id: 8
title: Umbrella Architecture
status: accepted
date: 2026-05-08
tags: [elixir, architecture, umbrella, project-structure]
description: "Default to a single Mix application. Promote to umbrella only when crossing one of three thresholds: multiple deployable surfaces with different runtime needs, a shared SDK consumed by multiple apps, or external-service ports that must not couple to each other. Umbrella overhead earns its keep when the boundaries are load-bearing."
---
# 008: Umbrella Architecture

Default to a single Mix application. Promote to umbrella only when bounded contexts demand compile-time separation enforced by the build system.

## Context

- Umbrella overhead is real: multiple `mix.exs` files, app-startup ordering, cross-app dependency graphs, separate test runners, shared-code placement decisions.
- The overhead earns its keep when the boundaries are structural: code in one app cannot accidentally import from another, deploy artifacts can differ per app, and the dependency graph is enforced.
- Conceptual separation alone ("the IO part," "the config part") is not load-bearing; directory conventions inside a single app do the same logical job without the structural cost.

## Consequence

- New projects start as a single Mix application with directory-level concern separation.
- Promoting to umbrella is a real migration, not a default trajectory.
- Single-concern tools (CLIs, local developer tools, single-purpose services) stay single-app regardless of LOC.

## Rules

- Start any new Elixir project as a single Mix application. Use `lib/<app>/<concern>/` directories to organize bounded concerns.
- Promote to umbrella only when crossing at least one threshold: (a) multiple deployable surfaces with different runtime needs (high-traffic web app + separately-scaled redirect engine sharing a DB); (b) a shared SDK consumed by multiple apps without circular references (Postgres SDK used by web, workers, redirect); (c) multiple external-service ports that must not couple (Stripe, Cloudflare, S3 in their own apps).
- The diagnostic when proposing a new app: would a code-level violation of this boundary be a real bug? If yes, umbrella the boundary. If "would be nicer to keep separate," directory conventions in a single app are the lighter answer.
- Umbrella shared-utility apps have ZERO domain knowledge. If you are importing a domain schema, it does not belong in `shared_utils`.

## DO

```
# Single-concern project: single Mix application
my_app/
├── mix.exs
├── lib/
│   └── my_app/
│       ├── orchestrator/
│       ├── notifications/
│       └── billing/
└── test/
```

```
# Multi-deployable SaaS: umbrella
my_saas/
├── mix.exs                      # umbrella
└── apps/
    ├── my_saas_pg/              # shared DB SDK
    ├── my_saas_web/             # web app
    ├── my_saas_redirect/        # separately-scaled engine
    ├── my_saas_payments/        # Stripe port
    ├── my_saas_storage/         # S3 port
    └── my_saas_shared/          # cross-cutting utils, no domain knowledge
```

## DON'T

```
# Why wrong: umbrella for a single-concern CLI; three apps with no
# load-bearing boundary between them.
my_cli/
├── mix.exs
└── apps/
    ├── my_cli_core/
    ├── my_cli_io/
    └── my_cli_config/
```

## Applies To
- `mix.exs`
- `apps/*/mix.exs`
