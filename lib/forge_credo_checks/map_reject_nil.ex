defmodule ForgeCredoChecks.MapRejectNil do
  use Credo.Check,
    base_priority: :high,
    category: :refactor,
    explanations: [
      check: """
      `Enum.reduce/3` fuses the common "map then drop nils" pattern
      LLMs produce into a single pass:

          things
          |> Enum.map(&parse/1)
          |> Enum.reject(&is_nil/1)

      becomes:

          Enum.reduce(things, [], fn x, acc ->
            case parse(x) do
              nil -> acc
              v -> [v | acc]
            end
          end)

      Add `|> Enum.reverse()` only if the output order matters.
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
            "`Enum.reduce/3` replaces `Enum.map/2 |> Enum.reject(&is_nil/1)` in one pass.",
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
