# Changelog

## Unreleased

### Added

- `ForgeCredoChecks.NoAnyOrTermTypes`: flags broad `any()` / `term()` uses in specs, callbacks, macrocallbacks, public/private/opaque type definitions, and nested type expressions so Dialyzer keeps useful shape information. Each finding carries the banned type's own column, so multiple broad types on a single spec or type line are reported as distinct, individually-actionable locations.
- `ForgeCredoChecks.TaintedSourceInspection`: flags `=~`, `String.contains?`, `Regex.*`, and `Code.eval_string` when they inspect text tainted from `File.read!` / `File.stream!` of non-test `.ex` / `.exs` source paths, while leaving terminal artifact reads quiet. Supports `:excluded_paths` for shrinking migration bridges.
- `ForgeCredoChecks.TimingAndPrivateStateGuard`: flags actual `Process.sleep/1` and `:sys.replace_state/2` call nodes while ignoring string, atom, and capture mentions. Supports `:excluded_paths` for shrinking migration bridges.

## 0.7.0 - 2026-07-03

### Added

- `ForgeCredoChecks.LargeStruct`: flags structs with 32 or more fields, which lose the BEAM's flat-map optimization.
- `ForgeCredoChecks.UnsupervisedSpawn`: flags raw `spawn`/`Task.start` of long-lived processes that belong under a supervisor. Supports `:excluded_paths` to skip files (e.g. test support) by path.
- `ForgeCredoChecks.NamespaceTrespassing`: flags defining your own modules inside a dependency's namespace.
- `ForgeCredoChecks.NoInlineRegex`: flags inline `~r`/`~R` regex sigils inside function bodies. Define regexes as module attributes so placement is machine-enforced instead of reviewer-attention work.
- `ForgeCredoChecks.PortProducerBoundary`: flags external-model producers (subprocess/HTTP dispatch) outside the set of declared boundary modules, so a new producer must be added to an explicit allow-list.
- `ForgeCredoChecks.NoSourceInspectionInTest`: flags tests that verify behaviour by reading or AST-parsing production source — `File.read!`/`File.stream!`/`Code.string_to_quoted` of a `lib/*.ex` path (literal or carried as data) — instead of exercising the real function. Catches both the literal-read and the data-carried-path + `Code.string_to_quoted` forms, while sparing data-only fixtures and meta-lints that parse only test source.

## 0.6.0

### Added

- `ForgeCredoChecks.MapGetWithOr`: flags `Map.get(_, _) || fallback`. Use `Map.get/3` for local defaults, or normalize the data once at the ingestion boundary.
- `ForgeCredoChecks.ChainedMapGet`: flags `Map.get(_, _) || Map.get(_, _)` at higher priority because fishing across multiple maps or key spellings signals an unresolved input-shape problem.

## 0.5.0

### Fixed

- `InconsistentParamNames`: clauses are now scoped per module. Previously, `def`/`defp` clauses were grouped by `{name, arity}` across the entire file, so two `defimpl` blocks for the same protocol (with idiomatically different parameter names like `office` vs `van_stop`) produced false positives. Clauses in separate `defmodule`, `defimpl`, or `defprotocol` blocks are now never cross-compared. Eliminates ~49% of false positives observed in production evaluation.
- `InconsistentParamNames`: multiple inconsistent positions in the same function now produce a single aggregated issue instead of one issue per position.
- `NoUnnecessaryCatchAllRaise`: single-clause functions that raise are no longer flagged. The rule's premise ("FunctionClauseError already provides better diagnostics") only applies when there is at least one other clause to fall through from. Stubs, arity redirects, and deliberately-raising test doubles are no longer false positives.
- `NoUnnecessaryCatchAllRaise`: sibling-clause counting is now scoped per module (same fix as `InconsistentParamNames`).
- `NoUnnecessaryCatchAllRaise`: message softened from "Remove this clause" to "Consider removing this clause, or narrowing the guard if the raise message documents valid inputs."
- `NoUnnecessaryCatchAllRaise`: check explanation now documents how to exclude test files via `.credo.exs` `files: %{excluded: [...]}` configuration.

## 0.4.0

Five new checks ported from [credence](https://hexdocs.pm/credence/) anti-pattern rules, adapted to integrate with the standard Credo runner (so `credo:disable-for-*` comments work and the rules participate in `mix credo --strict`):

- `ForgeCredoChecks.InconsistentParamNames`: flags multi-clause functions where the same positional argument has different base names across clauses (e.g. `current` in one clause, `prev` in another). Drift makes readers question correctness. Literal and destructuring patterns at a position cause that position to be skipped.
- `ForgeCredoChecks.NoKernelShadowing`: flags `=`/`fn`/`def` binding sites that shadow common `Kernel` functions (`max`, `min`, `length`, `elem`, `hd`, `tl`, `abs`, `round`, `trunc`, `div`, `rem`, `tuple_size`, `map_size`, `byte_size`, `bit_size`). Calls like `max(max, other)` become ambiguous to readers — rename the variable.
- `ForgeCredoChecks.NoUnnecessaryCatchAllRaise`: flags `def`/`defp` clauses where every argument is a wildcard AND the body is exactly `raise(...)`. Elixir's built-in `FunctionClauseError` already names the function and the failing arguments — a hand-written catch-all that raises a hardcoded message throws that signal away.
- `ForgeCredoChecks.NoCaseTrueFalse`: flags `case <bool_expr> do true -> ...; false -> ... end` (and variants with `_` as one clause). The `if/else` form makes the truthy branch obvious without a clause-scan. `case` on a plain variable is NOT flagged — that's typically a legitimate tristate match.
- `ForgeCredoChecks.NoKernelOpInPipeline`: flags `pipeline |> Kernel.<op>(arg)` for comparison and boolean operators (`==`, `!=`, `===`, `!==`, `<`, `>`, `<=`, `>=`, `and`, `or`). Use the operator in infix position. Arithmetic operators (`+`, `-`, `*`, `/`) are NOT flagged — they have legitimate uses in pipelines.

Auto-fix is NOT implemented for any of these checks; credo doesn't run auto-fixers, and source mutation introduces risk that's better handled by the operator at each call site.

## 0.3.0

Three new checks codifying conventions for the `with` macro:

- `ForgeCredoChecks.WithBareBinding`: every clause in a `with` chain must use `<-`, never `=`. Smuggled `=` bindings bypass the fall-through control flow that gives `with` its purpose.
- `ForgeCredoChecks.WithElseClauses`: flags `with` blocks whose `else` exceeds `:max_clauses` (default `1`, configurable). Wide `else` blocks become dispatch tables on step-specific error shapes; normalize each step's return in a helper instead.
- `ForgeCredoChecks.WithResultTag`: flags `<-` clauses whose atom-tagged LHS is outside `:allowed_atoms` (default `[:ok, :error]`, configurable). Codebases that use richer control-flow vocabulary (`:found`, `:retry`, `:locked`) extend the allowlist rather than disabling the check.

Check feedback rewritten for agent readers:

- Messages now lead with "Replace X with Y" instead of passive descriptions like "X is more efficient than Y", so an LLM reading a Credo issue gets a concrete edit instruction.
- Every explanation got a `## Why / ## How to fix / ## What NOT to do` structure with concrete BEFORE/AFTER snippets.
- The four `Enum`-chain checks (`MapReject`, `MapRejectNil`, `FilterMap`, `RejectMap`) now recommend **comprehensions first**, `Enum.flat_map/2` second (where the transform is naturally 0-or-more), and `Enum.reduce/3` only as a last resort. The `reduce + reverse` pattern is explicitly called out as an anti-pattern: paying a second pass just to undo the order an accumulator imposed is exactly the tax comprehensions exist to avoid.

## 0.2.0

First Hex release.

Adds four checks beyond the original two-pass `Enum` chain set:

- `ForgeCredoChecks.MapNewFromInto`: `Enum.map |> Enum.into(%{}, ...)` becomes `Map.new/2`
- `ForgeCredoChecks.MapNewFromReduce`: `Enum.reduce(_, %{}, &Map.put(acc, k, v))` becomes `Map.new/2`
- `ForgeCredoChecks.ReverseListFirst`: `xs |> Enum.reverse() |> List.first()` becomes `List.last(xs)`
- `ForgeCredoChecks.SortListFirst`: `Enum.sort |> List.first` becomes `Enum.min`/`Enum.max`/`*_by`

Carried over from 0.1.x:

- `ForgeCredoChecks.FilterMap`: `Enum.filter |> Enum.map`
- `ForgeCredoChecks.RejectMap`: `Enum.reject |> Enum.map`
- `ForgeCredoChecks.MapReject`: `Enum.map |> Enum.reject`
- `ForgeCredoChecks.MapRejectNil`: `Enum.map |> Enum.reject(&is_nil/1)`
