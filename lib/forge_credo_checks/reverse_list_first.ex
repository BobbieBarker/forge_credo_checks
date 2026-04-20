defmodule ForgeCredoChecks.ReverseListFirst do
  use Credo.Check,
    base_priority: :high,
    category: :refactor,
    explanations: [
      check: """
      `List.last/1` is equivalent to `Enum.reverse() |> List.first()` but
      makes the intent explicit and skips the intermediate reversed list.

      This:

          xs |> Enum.reverse() |> List.first()

      becomes:

          List.last(xs)

      Common LLM artifact: building an accumulator with `[v | acc]` then
      reversing at the end to get the original order, then taking the first
      element. The reverse round-trip is unnecessary; `List.last` directly
      returns the same value.
      """
    ]

  @doc false
  def run(source_file, params \\ []) do
    issue_meta = IssueMeta.for(source_file, params)
    Credo.Code.prewalk(source_file, &traverse(&1, &2, issue_meta))
  end

  # _ |> Enum.reverse() |> List.first()
  defp traverse(
         {:|>, _,
          [
            {:|>, _,
             [
               _,
               {{:., _, [{:__aliases__, _, [:Enum]}, :reverse]}, _, []}
             ]},
            {{:., _, [{:__aliases__, meta, [:List]}, :first]}, _, _}
          ]} = ast,
         issues,
         issue_meta
       ) do
    {ast, issues ++ List.wrap(issue_for(issue_meta, meta[:line]))}
  end

  # List.first(_ |> Enum.reverse())
  defp traverse(
         {{:., meta, [{:__aliases__, _, [:List]}, :first]}, _,
          [
            {:|>, _, [_, {{:., _, [{:__aliases__, _, [:Enum]}, :reverse]}, _, []}]}
            | _
          ]} = ast,
         issues,
         issue_meta
       ) do
    {ast, issues ++ List.wrap(issue_for(issue_meta, meta[:line]))}
  end

  # List.first(Enum.reverse(_))
  defp traverse(
         {{:., meta, [{:__aliases__, _, [:List]}, :first]}, _,
          [
            {{:., _, [{:__aliases__, _, [:Enum]}, :reverse]}, _, [_]}
            | _
          ]} = ast,
         issues,
         issue_meta
       ) do
    {ast, issues ++ List.wrap(issue_for(issue_meta, meta[:line]))}
  end

  defp traverse(ast, issues, _issue_meta), do: {ast, issues}

  defp issue_for(issue_meta, line_no) do
    format_issue(issue_meta,
      message: "`List.last(xs)` replaces `xs |> Enum.reverse() |> List.first()`.",
      trigger: "List.first",
      line_no: line_no
    )
  end
end
