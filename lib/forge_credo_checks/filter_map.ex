defmodule ForgeCredoChecks.FilterMap do
  use Credo.Check,
    base_priority: :high,
    category: :refactor,
    explanations: [
      check: """
      Replace `Enum.filter/2 |> Enum.map/2` with a comprehension.

      ## Why

      The pipe walks the list twice and allocates an intermediate list of
      matching elements before mapping. A comprehension does both in one
      pass, preserves order naturally, and avoids the `reduce + reverse`
      anti-pattern (paying a second traversal just to undo the order an
      accumulator imposed).

      ## How to fix (in order of preference)

      **Preferred: comprehension.**

          # BEFORE
          things
          |> Enum.filter(&keep?/1)
          |> Enum.map(&transform/1)

          # AFTER
          for x <- things, keep?(x), do: transform(x)

      One pass, in-order, no intermediate list, no reverse step.

      **Last resort: `Enum.reduce/3`.** Only when a comprehension is awkward
      *and* the consumer does not care about order (`Map.new`, `Enum.sum`,
      set membership, sort, count):

          Enum.reduce(things, [], fn x, acc ->
            if keep?(x), do: [transform(x) | acc], else: acc
          end)

      ## What NOT to do

      Do not switch to `Enum.reduce/3` and append `|> Enum.reverse/1` to
      restore order. That is exactly the tax the comprehension exists to
      avoid: you pay a second pass just to undo the `[h | acc]` reversal.
      If you need ordered output, use a comprehension.
      """
    ]

  alias ForgeCredoChecks.EnumChainWalker

  @doc false
  def run(source_file, params \\ []) do
    issue_meta = IssueMeta.for(source_file, params)

    report = fn line_no, _pred ->
      format_issue(issue_meta,
        message:
          "Replace `Enum.filter/2 |> Enum.map/2` with a comprehension: " <>
            "`for x <- things, keep?(x), do: transform(x)`. One pass, in-order, " <>
            "no intermediate list. Use `Enum.reduce/3` only when a comprehension is awkward " <>
            "AND the consumer does not care about order. Do NOT use `Enum.reduce/3 |> Enum.reverse/1` " <>
            "to restore order: the comprehension exists to avoid that second-pass tax.",
        trigger: "|>",
        line_no: line_no
      )
    end

    Credo.Code.prewalk(
      source_file,
      &EnumChainWalker.traverse(&1, &2, :filter, :map, report)
    )
  end
end
