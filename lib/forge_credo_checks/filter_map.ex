defmodule ForgeCredoChecks.FilterMap do
  use Credo.Check,
    base_priority: :high,
    category: :refactor,
    explanations: [
      check: """
      `Enum.flat_map/2` is more efficient than `Enum.filter/2 |> Enum.map/2`.

      The two-pass version walks the list twice and builds an intermediate
      list of matching elements before mapping. Fusing into `flat_map`
      visits each element once and yields `[mapped]` for matches, `[]`
      otherwise.

      This should be refactored:

          things
          |> Enum.filter(&keep?/1)
          |> Enum.map(&transform/1)

      to look like this:

          Enum.flat_map(things, fn x ->
            if keep?(x), do: [transform(x)], else: []
          end)

      Or, when both predicates and transforms are simple, use a comprehension:

          for x <- things, keep?(x), do: transform(x)
      """
    ]

  alias ForgeCredoChecks.EnumChainWalker

  @doc false
  def run(source_file, params \\ []) do
    issue_meta = IssueMeta.for(source_file, params)

    report = fn line_no, _pred ->
      format_issue(issue_meta,
        message:
          "`Enum.flat_map/2` is more efficient than `Enum.filter/2 |> Enum.map/2`.",
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
