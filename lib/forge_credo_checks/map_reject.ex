defmodule ForgeCredoChecks.MapReject do
  use Credo.Check,
    base_priority: :high,
    category: :refactor,
    explanations: [
      check: """
      `Enum.reduce/3` is more efficient than `Enum.map/2 |> Enum.reject/2`.

      Two iterations and an intermediate list become one pass:

          things
          |> Enum.map(&transform/1)
          |> Enum.reject(&drop?/1)

      becomes:

          Enum.reduce(things, [], fn x, acc ->
            v = transform(x)
            if drop?(v), do: acc, else: [v | acc]
          end)

      Add `|> Enum.reverse()` only if the output order matters.

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
          "`Enum.reduce/3` is more efficient than `Enum.map/2 |> Enum.reject/2`.",
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
