defmodule ForgeCredoChecks.MapRejectNil do
  use Credo.Check,
    base_priority: :high,
    category: :refactor,
    explanations: [
      check: """
      `Enum.flat_map/2` is the canonical replacement for the common
      "map then drop nils" pattern produced by LLMs:

          things
          |> Enum.map(&parse/1)
          |> Enum.reject(&is_nil/1)

      Use `flat_map` to fuse parse + filter into one pass:

          Enum.flat_map(things, fn x ->
            case parse(x) do
              nil -> []
              parsed -> [parsed]
            end
          end)

      Or, when `parse` already returns a list/option:

          Enum.flat_map(things, &List.wrap(parse(&1)))
      """
    ]

  alias ForgeCredoChecks.EnumChainWalker

  @doc false
  def run(source_file, params \\ []) do
    issue_meta = IssueMeta.for(source_file, params)

    report = fn line_no, pred ->
      if EnumChainWalker.is_nil_predicate?(pred) do
        format_issue(issue_meta,
          message:
            "`Enum.flat_map/2` replaces `Enum.map/2 |> Enum.reject(&is_nil/1)` in one pass.",
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
