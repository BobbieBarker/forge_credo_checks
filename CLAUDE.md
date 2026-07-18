# forge_credo_checks

Custom Credo checks for the Forge ecosystem. Each check is a standalone Credo check module that enforces project-specific coding standards across Forge projects.

## Critical Rules

These rules are the most frequently violated by agents. Read and internalize before writing any code.

1. **Every public function has `@doc`, `@spec`, and doctests** - The public API is the product. Every exported function must have a `@doc` with at least one doctest example, a `@spec`, and clear parameter descriptions.
2. **Provide bang (`!`) variants for all fallible public functions** - If `foo/1` returns `{:ok, value} | {:error, reason}`, also provide `foo!/1` that unwraps or raises. Use a consistent pattern (e.g., a `bang!` helper macro or manual unwrap).
3. **Every public function returns result tuples** - `{:ok, value} | {:error, reason}`. No bare values, no raising (except bang variants). Use `@type t_res(t) :: {:ok, t} | {:error, term()}` for specs.
4. **Write tests first (TDD)** - Write a failing test, then implement. Never write implementation without a test that exercises it. For bug fixes, reproduce the bug as a test first.
5. **Test through the public API only** - Never test internal functions or private helpers. Tests exercise only the module's public API.
6. **No `else` in `with` expressions** - Let non-matching values fall through. Normalize errors in helper functions, not in `else` blocks. The only exception is collapsing all outcomes to a single binary result.
7. **Assert ALL side effects in tests** - Return values, raised exceptions, side effects. Missing assertions hide bugs.
8. **Run CI before pushing** - `mix format --check-formatted && mix credo --strict && mix compile --warnings-as-errors && MIX_ENV=dev mix dialyzer && mix test` must pass. No exceptions.

## Architecture

This is a standalone Elixir library with a flat `lib/` structure. There are no umbrella apps, no database, no web layer, and no supervision trees.

### Module Structure

- `lib/forge_credo_checks/` - All source modules
- `test/` - ExUnit tests mirroring `lib/` structure
- Root module (`lib/forge_credo_checks.ex`) - Public API entry point. Callers use this module exclusively.

### Module Taxonomy

1. **Public API module** (root) - The main entry point. All public functions live here or are delegated here via `defdelegate`. Callers never reach into submodules.
2. **Internal modules** - Implementation details under `lib/forge_credo_checks/`. All get `@moduledoc false`. Never called directly by consumers.
3. **Type modules** - Shared type definitions and structs. Public structs get `@moduledoc` and `@type t`.

### Credo Check Structure

Each check is a module under `ForgeCredoChecks` that `use Credo.Check`. Checks follow the standard Credo check pattern:
- `@explanation` module attribute with check documentation
- `run/2` callback that receives the source file and params
- Issue creation via `Credo.Issue` structs
- Configurable via `.credo.exs` in consuming projects

## Stack

- Elixir 1.20 / OTP 28
- No database, no web framework, no job processing
- Key focus: correctness, performance, documentation, hex.pm packaging

## Conventions

### Code Style
- Run `mix format` before committing
- `mix credo --strict` must pass with zero issues
- `--warnings-as-errors` on compile in CI
- No inline regex literals in function bodies - extract to `@module_attribute` or named constant

### Pragmatic Functional Programming
- Point-free/tacit style preferred - functions compose via pipes, not intermediate variables
- Side effects must be explicit, never hidden inside pure-looking functions
- Don't over-abstract - three similar lines is better than a premature abstraction
- `with` over nested `case` for sequential fallible operations
- Multiple function clauses over conditionals inside a single function body

### with Expressions
- **Avoid `else` clauses.** A bare `with` that lets non-matching values pass through is almost always preferable.
- **The fix for "I need else":** encapsulate error handling in the called functions themselves. Each step returns either `{:ok, value}` (continue) or a fully-formed error response (falls through as the `with` return).
- **Only acceptable `else`:** collapsing all outcomes to a single binary result (e.g., `_ -> false` or `_ -> :error`) where you genuinely don't care which step failed.

### TDD for Implementation
Write a failing test first, then implement until it passes. This applies to both new features and bug fixes. For bug fixes: reproduce the bug as a test assertion, then fix. Never write implementation code without a test that exercises it.

### Testing
- Tests go in `test/` mirroring `lib/` structure
- Use `async: true` on all test modules unless there is a documented reason not to
- Test through the public API only - never test internal/private functions
- Prefer pattern matching assertions: `assert {:ok, %Result{value: ^expected}} = MyLib.function(input)`
- Use equality assertions (`==`) only for `refute` or when pattern matching isn't possible
- **Assert ALL side effects**: return values, raised exceptions (for bang variants), error tuples
- **Don't test what you don't own**: Don't test Elixir stdlib or dependency internals
- **Don't test observability**: Never write assertions on telemetry emissions or log output
- **Tests should be `async: true` by default.** If you set `async: false`, add a comment explaining why.
- **Use property-based testing** (StreamData) for math-heavy or algorithmic functions - enumerate edge cases, verify invariants over generated inputs
- **Doctests are tests** - every `@doc` example is compiled and run by ExUnit. Keep them accurate and representative.

### Public API Design
- The root module is the only public interface. All public functions live there or are delegated via `defdelegate`.
- Every public function gets `@doc` with at least one doctest, `@spec`, and clear parameter docs.
- Provide bang (`!`) variants for all fallible functions: `foo/1` returns `{:ok, v} | {:error, r}`, `foo!/1` unwraps or raises `ArgumentError`.
- Use `@moduledoc false` on all internal modules.
- Define `@type t` on all public structs.

### hex.pm Packaging
- Keep `mix.exs` metadata complete: `:description`, `:licenses`, `:links`, `:source_url`, `:homepage_url`
- Maintain a `CHANGELOG.md` with Keep a Changelog format
- Use `ex_doc` for documentation - configure `:groups_for_modules` and `:extras` in `mix.exs`
- Version follows SemVer: breaking changes bump major, new features bump minor, fixes bump patch
- `@moduledoc` on every public module - this is what appears on hexdocs

### Git
- One commit per PR (squash before review)
- Branch naming: `FGE-{number}` for tickets, `chore/description` for infrastructure
- **Commit messages and PR bodies MUST include `Fixes FGE-{number}`** - this triggers Linear's GitHub integration to auto-transition tickets to Done on merge
- Never force push to main

## CI Pipeline

CI runs on every PR: `mix test`, `mix format --check-formatted`, `mix credo --strict`, `mix dialyzer`, `mix compile --warnings-as-errors`, Codecov diff coverage.

When fixing CI failures, do NOT modify files in `.github/workflows/`.
