defmodule ForgeCredoChecks.RejectMap do
  use Credo.Check,
    base_priority: :high,
    category: :refactor,
    explanations: [
      check: """
      `Enum.reduce/3` is more efficient than `Enum.reject/2 |> Enum.map/2`.

      The two-pass version walks the list twice and allocates an
      intermediate list of surviving elements before mapping. A single
      `Enum.reduce/3` visits each element once with no intermediate list:

          things
          |> Enum.reject(&drop?/1)
          |> Enum.map(&transform/1)

      becomes:

          Enum.reduce(things, [], fn x, acc ->
            if drop?(x), do: acc, else: [transform(x) | acc]
          end)

      Add `|> Enum.reverse()` only if the output order matters.
      """
    ]

  alias ForgeCredoChecks.EnumChainWalker

  @doc false
  def run(source_file, params \\ []) do
    issue_meta = IssueMeta.for(source_file, params)

    report = fn line_no, _pred ->
      format_issue(issue_meta,
        message:
          "`Enum.reduce/3` is more efficient than `Enum.reject/2 |> Enum.map/2`.",
        trigger: "|>",
        line_no: line_no
      )
    end

    Credo.Code.prewalk(
      source_file,
      &EnumChainWalker.traverse(&1, &2, :reject, :map, report)
    )
  end
end
