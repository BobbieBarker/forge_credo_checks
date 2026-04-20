defmodule ForgeCredoChecks.SortListFirst do
  use Credo.Check,
    base_priority: :high,
    category: :refactor,
    explanations: [
      check: """
      Sorting a whole list to take the first or last element is O(N log N)
      when O(N) suffices via `Enum.min`, `Enum.max`, `Enum.min_by`, or
      `Enum.max_by`.

      Replacements:

      | This | Becomes |
      |---|---|
      | `Enum.sort(xs) \\| List.first()` | `Enum.min(xs)` |
      | `Enum.sort(xs) \\| List.last()` | `Enum.max(xs)` |
      | `Enum.sort(xs, :desc) \\| List.first()` | `Enum.max(xs)` |
      | `Enum.sort_by(xs, f) \\| List.first()` | `Enum.min_by(xs, f)` |
      | `Enum.sort_by(xs, f, :desc) \\| List.first()` | `Enum.max_by(xs, f)` |

      A full sort is wasted work when only the extremum is needed.
      """
    ]

  @doc false
  def run(source_file, params \\ []) do
    issue_meta = IssueMeta.for(source_file, params)
    Credo.Code.prewalk(source_file, &traverse(&1, &2, issue_meta))
  end

  @sort_funs [:sort, :sort_by]
  @terminal_funs [:first, :last]

  # _ |> Enum.sort(...) |> List.first()
  defp traverse(
         {:|>, _,
          [
            {:|>, _,
             [
               _,
               {{:., _, [{:__aliases__, _, [:Enum]}, sort_fun]}, _, _}
             ]},
            {{:., _, [{:__aliases__, meta, [:List]}, term]}, _, _}
          ]} = ast,
         issues,
         issue_meta
       )
       when sort_fun in @sort_funs and term in @terminal_funs do
    {ast, issues ++ List.wrap(issue_for(issue_meta, meta[:line], sort_fun, term))}
  end

  # List.first(Enum.sort(...)) — also handles List.first(Enum.sort_by(...))
  defp traverse(
         {{:., meta, [{:__aliases__, _, [:List]}, term]}, _,
          [
            {{:., _, [{:__aliases__, _, [:Enum]}, sort_fun]}, _, _}
            | _
          ]} = ast,
         issues,
         issue_meta
       )
       when sort_fun in @sort_funs and term in @terminal_funs do
    {ast, issues ++ List.wrap(issue_for(issue_meta, meta[:line], sort_fun, term))}
  end

  defp traverse(ast, issues, _issue_meta), do: {ast, issues}

  defp issue_for(issue_meta, line_no, sort_fun, term) do
    format_issue(issue_meta,
      message:
        "`Enum.#{replacement(sort_fun, term)}` replaces `Enum.#{sort_fun} |> List.#{term}` " <>
          "(O(N) instead of O(N log N)).",
      trigger: "List.#{term}",
      line_no: line_no
    )
  end

  defp replacement(:sort, :first), do: "min/1"
  defp replacement(:sort, :last), do: "max/1"
  defp replacement(:sort_by, :first), do: "min_by/2"
  defp replacement(:sort_by, :last), do: "max_by/2"
end
