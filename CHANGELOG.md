# Changelog

## Unreleased

### Added

- `ForgeCredoChecks.NoTelemetryAssertionsInTest`: flags telemetry handler attachment and telemetry-event assertions in tests so behavioral outcomes remain the test contract. The `:telemetry_event_roots` parameter declares project event-name roots explicitly while retaining the existing six-root default.
- `ForgeCredoChecks.NoGlobalPubSubWildcardRefute`: flags wildcard negative assertions for events delivered through global PubSub subscriptions, where unrelated async producers can invalidate the assertion.
- `ForgeCredoChecks.NoDetsInfoOpenGuard`: flags `:dets.info/1` comparisons with `:undefined` that gate `:dets.open_file/2`, because the registry read does not register the caller as a DETS user.

### Changed

- `ForgeCredoChecks.NoGlobalPubSubWildcardRefute`: closed four detection gaps that let a rename silence the check. Any unbound payload variable is now a wildcard, not just one starting with `_` (`meta` is as unpinned as `_meta`); `refute_received` is handled alongside `refute_receive`; tuples of three or more elements are matched (they are `{:{}, meta, args}` in the AST, not literal tuples); and a subscription taken as a bare imported local call (`subscribe_mcp()`) is recognised alongside the qualified form. A pinned or destructured payload field and a scoped, non-zero-arity subscription remain unflagged. Also renamed the source file to `no_global_pub_sub_wildcard_refute.ex` to match `Macro.underscore/1`, and fixed a `FunctionClauseError` raised on a source file with a nil filename.
- `ForgeCredoChecks.NoDetsInfoOpenGuard`: now flags the guard when the `:dets.info/1` result is bound to a variable first (`info = :dets.info(table)` then `info !== :undefined`) — previously the most natural edit an agent makes when told the comparison is the problem, and one that defeated detection entirely. Tracks single-assignment bindings within the enclosing function body only; rebound names are not tracked and bindings do not leak into sibling bodies. Arity-2 `:dets.info/2` and comparisons against values other than `:undefined` remain unflagged.
- `ForgeCredoChecks.NoTelemetryAssertionsInTest`: now resolves event names lifted into a module attribute in the same file (`@event [:my_app, :thing, :done]` then `assert_receive {@event, ...}`), flags attachment routed through `apply/3`, and matches two-element telemetry messages such as `{:telemetry, payload}` — which are literal tuples in the AST rather than `{:{}, meta, args}` and so were previously missed.
- `ForgeCredoChecks.TimingAndPrivateStateGuard`: now flags `:timer.sleep/1` (the same function as `Process.sleep/1` under another name), including its piped form, and the `apply/3` route to every guarded call (`apply(:sys, :get_state, [pid])` and the equivalents for `:sys.replace_state`, `:timer.sleep`, and `Process.sleep`). A test-only `GenServer.call(pid, :__test_state__)` is deliberately not detected — no reliable AST signature distinguishes it from a genuine domain message — and is ruled out in the check's guidance instead.
- `ForgeCredoChecks.NoDetsInfoOpenGuard`, `ForgeCredoChecks.NoGlobalPubSubWildcardRefute`, and `ForgeCredoChecks.NoTelemetryAssertionsInTest`: moved all hand-written `@moduledoc` prose into `explanations[:check]` and deleted the `@moduledoc`. `use Credo.Check` overwrites `@moduledoc`, so that prose reached neither hexdocs nor `mix credo explain` — only `explanations[:check]` is rendered. Each check now also carries `## Bad` / `## Good` examples with copy-pasteable replacement code, and states which "fixes" are not fixes (deleting a `:telemetry.attach` and orphaning its assertions; widening a `refute_receive`; calling `:dets.info/1` for effect).
- `ForgeCredoChecks.NoGlobalPubSubWildcardRefute`: the previously hardcoded set of globally subscribed events is now the `:global_subscriptions` parameter, so projects other than the one it was extracted from can declare their own subscribe functions and event tags instead of silently getting a no-op check. The former hardcoded values remain the default.
- `ForgeCredoChecks.TimingAndPrivateStateGuard`: removed the project-specific `contracts/template_variables_contract_test.exs` path from every emitted message — it does not exist in consuming projects. Messages are now per-trigger and name concrete alternatives (`assert_receive` on a real message, `Process.monitor` plus `assert_receive {:DOWN, ...}`, or a deliberately public documented accessor), drop the check-internal trivia about string/atom/comment/capture mentions, and state explicitly that adding a test-only `handle_call(:__test_state__, _, state)` clause to production code is not an acceptable replacement for `:sys.get_state`.
- `ForgeCredoChecks.NoSourceInspectionInTest`: directs callers to reshape the public API by splitting a function or exposing the tested concept intentionally, rather than exporting a private implementation detail solely for tests.
- `ForgeCredoChecks.TimingAndPrivateStateGuard`: now also flags `:sys.get_state` call nodes at AST arities zero through two, covering direct `/1,2` calls and both piped forms while leaving string, atom, comment, and function-capture mentions untouched.

## 0.8.0 - 2026-07-14

### Added

- `ForgeCredoChecks.OneModulePerFile`: flags every literal `defmodule` after the first in a source file, including nested and reopened module declarations, while ignoring quoted module AST generated by macros. Files under `test/` and files ending in `_test.exs` are excluded by default because tests sometimes need nested fixture modules; configure `:excluded_paths` or set it to `[]` to enforce the rule there too.

- `ForgeCredoChecks.MultilineStringConcat`: flags a multi-line `<>` chain of two or more plain string literals (`"a" <> "b" <> "c"` spread across source lines) and suggests an Elixir heredoc. Only fires when every operand is a static string binary and the chain spans more than one source line, so `"prefix " <> some_var`, single-line `<>` of literals, and chains with an interpolated operand (`"a" <> "b#{x}"`) are left alone. Emits exactly one issue per chain by neutralizing the matched subtree.

- `ForgeCredoChecks.NoApplicationGetEnvInLib`: flags `Application.get_env/2,3` inside `lib/` (default scope), where `Application.compile_env/2,3` is the correct reader for compile-time values. `get_env` silently returns `nil` or a stale value when the app env is not yet loaded, a bug class that is silent in `mix` and surfaces only in a packaged release. `compile_env` is excluded by construction (only `:get_env` is matched), not by allowlist. Supports `included_paths` (default `[~r"^lib/"]`) to narrow scope and `allowed_paths` (default `[]`) to permit the rare `lib/` module that legitimately reads runtime config. `fetch_env`/`fetch_env!` are deliberately out of scope.
- `ForgeCredoChecks.TelemetryControlFlow`: flags `:telemetry.attach`/`attach_many` with an inline anonymous-function handler that performs control flow (`send/2`, `:erlang.send/2`, `GenServer.call`/`cast`) instead of observation-only recording. Now also detects **same-file function captures** (`&func/arity`, `&__MODULE__.func/arity`) by resolving the captured function's body within the same source file and inspecting it for control-flow calls. A raising telemetry handler is auto-detached by the runtime, so using the bus to deliver load-bearing signals fails silently; the idiomatic mechanism is `Phoenix.PubSub`. Cross-module captures and MFA-tuple handlers remain out of scope. Supports `:excluded_paths` as a shrinking migration bridge; `# credo:disable-for-next-line` is honored for intentional exceptions.
- `ForgeCredoChecks.NoAnyOrTermTypes`: flags broad `any()` / `term()` uses in specs, callbacks, macrocallbacks, public/private/opaque type definitions, and nested type expressions so Dialyzer keeps useful shape information. Each finding carries the banned type's own column, so multiple broad types on a single spec or type line are reported as distinct, individually-actionable locations.
- `ForgeCredoChecks.TaintedSourceInspection`: flags `=~`, `String.contains?`, `Regex.*`, and `Code.eval_string` when they inspect text tainted from `File.read!` / `File.stream!` of non-test `.ex` / `.exs` source paths, while leaving terminal artifact reads quiet. Supports `:excluded_paths` for shrinking migration bridges.
- `ForgeCredoChecks.TimingAndPrivateStateGuard`: flags actual `Process.sleep/1`, `:sys.replace_state/2`, and `:sys.get_state/1,2` call nodes while ignoring string, atom, comment, and capture mentions. Supports `:excluded_paths` for shrinking migration bridges.

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
