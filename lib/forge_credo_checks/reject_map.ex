defmodule ForgeCredoChecks.RejectMap do
  use Credo.Check,
    base_priority: :high,
    category: :refactor,
    explanations: [
      check: """
      `Enum.flat_map/2` is more efficient than `Enum.reject/2 |> Enum.map/2`.

      The two-pass version walks the list twice and builds an intermediate
      list of surviving elements before mapping. Fusing into `flat_map`
      visits each element once and yields `[mapped]` when the predicate
      is false, `[]` when true.

      This should be refactored:

          things
          |> Enum.reject(&drop?/1)
          |> Enum.map(&transform/1)

      to look like this:

          Enum.flat_map(things, fn x ->
            if drop?(x), do: [], else: [transform(x)]
          end)
      """
    ]

  alias ForgeCredoChecks.EnumChainWalker

  @doc false
  def run(source_file, params \\ []) do
    issue_meta = IssueMeta.for(source_file, params)

    report = fn line_no, _pred ->
      format_issue(issue_meta,
        message:
          "`Enum.flat_map/2` is more efficient than `Enum.reject/2 |> Enum.map/2`.",
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
