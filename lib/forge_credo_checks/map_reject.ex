defmodule ForgeCredoChecks.MapReject do
  use Credo.Check,
    base_priority: :high,
    category: :refactor,
    explanations: [
      check: """
      Replace `Enum.map/2 |> Enum.reject/2` with a comprehension.

      ## Why

      The pipe walks the list twice and allocates an intermediate list of
      transformed elements before rejection. A comprehension fuses both
      steps in one pass, preserves order naturally, and avoids the
      `reduce + reverse` anti-pattern.

      ## How to fix (in order of preference)

      **Preferred: comprehension.** A `=` binding inside a comprehension
      lets you compute the transformed value once and filter on it:

          # BEFORE
          things
          |> Enum.map(&transform/1)
          |> Enum.reject(&drop?/1)

          # AFTER
          for x <- things, v = transform(x), not drop?(v), do: v

      One pass, in-order, no intermediate list, no reverse step.

      **Last resort: `Enum.reduce/3`.** Only when a comprehension is awkward
      *and* the consumer does not care about order:

          Enum.reduce(things, [], fn x, acc ->
            v = transform(x)
            if drop?(v), do: acc, else: [v | acc]
          end)

      ## What NOT to do

      Do not switch to `Enum.reduce/3` and append `|> Enum.reverse/1` to
      restore order. That second pass is exactly the cost the comprehension
      exists to avoid.

      For the common `map |> reject(&is_nil/1)` case, see also
      `ForgeCredoChecks.MapRejectNil` which targets that specific shape.
      """
    ]

  alias ForgeCredoChecks.EnumChainWalker

  @doc false
  def run(source_file, params \\ []) do
    issue_meta = IssueMeta.for(source_file, params)

    report = fn line_no, _pred ->
      format_issue(issue_meta,
        message:
          "Replace `Enum.map/2 |> Enum.reject/2` with a comprehension: " <>
            "`for x <- things, v = transform(x), not drop?(v), do: v`. One pass, in-order, " <>
            "no intermediate list. Use `Enum.reduce/3` only when a comprehension is awkward " <>
            "AND the consumer does not care about order. Do NOT use `Enum.reduce/3 |> Enum.reverse/1` " <>
            "to restore order: the comprehension exists to avoid that second-pass tax.",
        trigger: "|>",
        line_no: line_no
      )
    end

    Credo.Code.prewalk(
      source_file,
      &EnumChainWalker.traverse(&1, &2, :map, :reject, report)
    )
  end
end
