# Changelog

## 0.4.0

Five new checks catching common anti-patterns in LLM-generated Elixir:

- `ForgeCredoChecks.InconsistentParamNames`: flags multi-clause functions where the same positional argument has different base names across clauses (e.g. `current` in one clause, `prev` in another). Drift makes readers question correctness. Literal and destructuring patterns at a position cause that position to be skipped.
- `ForgeCredoChecks.NoKernelShadowing`: flags `=`/`fn`/`def` binding sites that shadow common `Kernel` functions (`max`, `min`, `length`, `elem`, `hd`, `tl`, `abs`, `round`, `trunc`, `div`, `rem`, `tuple_size`, `map_size`, `byte_size`, `bit_size`). Calls like `max(max, other)` become ambiguous to readers — rename the variable.
- `ForgeCredoChecks.NoUnnecessaryCatchAllRaise`: flags `def`/`defp` clauses where every argument is a wildcard AND the body is exactly `raise(...)`. Elixir's built-in `FunctionClauseError` already names the function and the failing arguments — a hand-written catch-all that raises a hardcoded message throws that signal away.
- `ForgeCredoChecks.NoCaseTrueFalse`: flags `case <bool_expr> do true -> ...; false -> ... end` (and variants with `_` as one clause). The `if/else` form makes the truthy branch obvious without a clause-scan. `case` on a plain variable is NOT flagged — that's typically a legitimate tristate match.
- `ForgeCredoChecks.NoKernelOpInPipeline`: flags `pipeline |> Kernel.<op>(arg)` for comparison and boolean operators (`==`, `!=`, `===`, `!==`, `<`, `>`, `<=`, `>=`, `and`, `or`). Use the operator in infix position. Arithmetic operators (`+`, `-`, `*`, `/`) are NOT flagged — they have legitimate uses in pipelines.

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
