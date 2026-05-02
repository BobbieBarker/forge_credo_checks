defmodule ForgeCredoChecks.MapRejectNil do
  use Credo.Check,
    base_priority: :high,
    category: :refactor,
    explanations: [
      check: """
      Replace `Enum.map/2 |> Enum.reject(&is_nil/1)` with a comprehension
      or `Enum.flat_map/2`.

      ## Why

      The pipe walks the list twice and allocates an intermediate list that
      contains the nils that will be discarded next. A comprehension or
      `flat_map` fuses both steps in one pass, preserves order naturally,
      and avoids the `reduce + reverse` anti-pattern.

      ## How to fix (in order of preference)

      **Preferred: comprehension.** A `=` binding inside the comprehension
      computes the value once and filters on it:

          # BEFORE
          things
          |> Enum.map(&parse/1)
          |> Enum.reject(&is_nil/1)

          # AFTER
          for x <- things, v = parse(x), not is_nil(v), do: v

      One pass, in-order, no intermediate list, no reverse step.

      **Also good: `Enum.flat_map/2`.** Especially natural when `parse/1`
      conceptually returns "0-or-1 results":

          Enum.flat_map(things, fn x ->
            case parse(x) do
              nil -> []
              v -> [v]
            end
          end)

      Also one pass, in-order, no reverse.

      **Last resort: `Enum.reduce/3`.** Only when neither shape fits *and*
      the consumer does not care about order:

          Enum.reduce(things, [], fn x, acc ->
            case parse(x) do
              nil -> acc
              v -> [v | acc]
            end
          end)

      ## What NOT to do

      Do not switch to `Enum.reduce/3` and append `|> Enum.reverse/1` to
      restore order. That second pass is exactly the cost the comprehension
      and `flat_map` exist to avoid.
      """
    ]

  alias ForgeCredoChecks.EnumChainWalker

  @doc false
  def run(source_file, params \\ []) do
    issue_meta = IssueMeta.for(source_file, params)

    report = fn line_no, pred ->
      if EnumChainWalker.nil_predicate?(pred) do
        format_issue(issue_meta,
          message:
            "Replace `Enum.map/2 |> Enum.reject(&is_nil/1)` with a comprehension: " <>
              "`for x <- things, v = parse(x), not is_nil(v), do: v`. One pass, in-order, " <>
              "no intermediate list. `Enum.flat_map/2` returning `[]` for nil is also good. " <>
              "Use `Enum.reduce/3` only as a last resort when neither fits AND the consumer " <>
              "does not care about order. Do NOT use `Enum.reduce/3 |> Enum.reverse/1` to " <>
              "restore order: comprehension and flat_map exist to avoid that second-pass tax.",
          trigger: "|>",
          line_no: line_no
        )
      end
    end

    Credo.Code.prewalk(
      source_file,
      &EnumChainWalker.traverse(&1, &2, :map, :reject, report)
    )
  end
end
