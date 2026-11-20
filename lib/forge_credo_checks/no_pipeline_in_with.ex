defmodule ForgeCredoChecks.NoPipelineInWith do
  use Credo.Check,
    base_priority: :high,
    category: :refactor,
    explanations: [
      check: """
      Do not compose a pipeline anywhere in a `with` clause.

      Keep each clause focused on one named operation and its result contract.
      Extract the pipeline into a helper so the chain exposes the operation's
      purpose without mixing data transformations with fallible control flow.

          # Bad
          with {:ok, value} <- input |> normalize() |> validate() do
            {:ok, value}
          end

          # Good
          with {:ok, value} <- normalize_and_validate(input) do
            {:ok, value}
          end

          defp normalize_and_validate(input) do
            input |> normalize() |> validate()
          end

      A helper must preserve the pipeline's return value and evaluation order.
      Do not wrap a result in `{:ok, ...}` merely to satisfy a pattern match.

      Scans complete clause expressions, including call arguments, tuples,
      collections, captures, and anonymous function bodies. Reports one issue
      per offending clause, regardless of pipeline length or nesting depth.
      Parentheses and wrapping a pipeline in a call or result tuple do not
      exempt it.

      Each `with` owns its clause chain: its `do` and `else` bodies remain
      unrestricted. Nested `with` expressions are checked independently without
      duplicate reports. Other expressions nested in a clause (including `if`
      and `case` blocks) are part of that clause. There are no check-specific
      options.
      """
    ]

  @doc false
  def run(source_file, params \\ []) do
    issue_meta = IssueMeta.for(source_file, params)
    Credo.Code.prewalk(source_file, &traverse(&1, &2, issue_meta))
  end

  defp traverse({:with, _meta, args} = ast, issues, issue_meta)
       when is_list(args) and args != [] do
    {clauses, [body]} = Enum.split(args, -1)

    new_issues =
      if is_list(body) and Keyword.keyword?(body) and Keyword.has_key?(body, :do) do
        Enum.flat_map(clauses, &issue_for_clause(&1, issue_meta))
      else
        []
      end

    {ast, issues ++ new_issues}
  end

  defp traverse(ast, issues, _issue_meta), do: {ast, issues}

  defp issue_for_clause(clause, issue_meta) do
    {_ast, pipeline_meta} = Macro.prewalk(clause, nil, &find_pipeline/2)

    case pipeline_meta do
      nil -> []
      meta -> [pipeline_issue(meta, issue_meta)]
    end
  end

  defp find_pipeline({:with, _meta, args} = ast, found)
       when is_list(args) and args != [] do
    body = List.last(args)

    if is_list(body) and Keyword.keyword?(body) and Keyword.has_key?(body, :do) do
      {nil, found}
    else
      {ast, found}
    end
  end

  defp find_pipeline({:|>, meta, [_lhs, _rhs]}, found), do: {nil, found || meta}
  defp find_pipeline(ast, found), do: {ast, found}

  defp pipeline_issue(meta, issue_meta) do
    format_issue(issue_meta,
      message:
        "Do not use `|>` anywhere in a `with` clause, including nested expressions. " <>
          "Extract the composed operation into a named helper and call it from the clause. " <>
          "Preserve its return value, error behavior, and evaluation order. " <>
          "Do not hide the pipeline in arguments, anonymous functions, or `{:ok, ...}` wrappers. " <>
          "Pipelines in the `with` do/else bodies are allowed.",
      trigger: "|>",
      line_no: meta[:line],
      column: meta[:column]
    )
  end
end
