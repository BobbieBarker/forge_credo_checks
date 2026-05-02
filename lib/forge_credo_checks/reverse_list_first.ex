defmodule ForgeCredoChecks.ReverseListFirst do
  use Credo.Check,
    base_priority: :high,
    category: :refactor,
    explanations: [
      check: """
      Replace `xs |> Enum.reverse() |> List.first()` with `List.last(xs)`.

      ## Why

      `List.last/1` returns the same value directly, without allocating the
      reversed list. Common LLM artifact: building an accumulator with
      `[v | acc]`, reversing at the end to restore order, then taking the
      first element. The reverse round-trip is wasted work.

      ## How to fix

          # BEFORE
          xs |> Enum.reverse() |> List.first()

          # AFTER
          List.last(xs)

      Both nested and piped forms are flagged:

          List.first(Enum.reverse(xs))   # also flagged
          List.first(xs |> Enum.reverse())  # also flagged
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
      message:
        "Replace `xs |> Enum.reverse() |> List.first()` with `List.last(xs)`. " <>
          "Both return the same element; `List.last/1` skips allocating the reversed list.",
      trigger: "List.first",
      line_no: line_no
    )
  end
end
