defmodule ForgeCredoChecks.NoCaseTrueFalse do
  use Credo.Check,
    base_priority: :high,
    category: :refactor,
    explanations: [
      check: """
      `case` on a boolean expression with `true`/`false` clauses should be `if/else`.

      ## Why

      LLMs frequently transliterate Python's `if/else` through a `case` on a
      boolean expression with explicit `true`/`false` clauses. Idiomatic
      Elixir uses `if/else` when the condition is already a boolean — the
      reader doesn't have to scan to determine which clause is the truthy
      branch.

      Only `case` whose subject is a *boolean expression* (comparison,
      operator, function call) is flagged. A `case` on a plain variable is
      assumed to be a legitimate pattern match on a tristate value (e.g.
      `nil` plus the booleans) and is not flagged.

      ## Bad

          case rem(n, 2) == 0 do
            true -> :even
            false -> :odd
          end

      ## Good

          if rem(n, 2) == 0 do
            :even
          else
            :odd
          end

      ## Also flagged

          case expr do true -> a; _ -> b end
          case expr do false -> b; _ -> a end
      """
    ]

  @doc false
  def run(source_file, params \\ []) do
    issue_meta = IssueMeta.for(source_file, params)
    Credo.Code.prewalk(source_file, &traverse(&1, &2, issue_meta))
  end

  defp traverse({:case, meta, [subject, [do: [clause_a, clause_b]]]} = ast, issues, issue_meta) do
    if not plain_variable?(subject) and
         boolean_clause_pair?(clause_pattern(clause_a), clause_pattern(clause_b)) do
      issue =
        format_issue(issue_meta,
          message:
            "`case` on a boolean expression with `true`/`false` clauses should be `if/else`. " <>
              "Use `if cond, do: ..., else: ...` so readers don't have to scan the clauses to " <>
              "determine which branch is the truthy one.",
          trigger: "case",
          line_no: Keyword.get(meta, :line)
        )

      {ast, [issue | issues]}
    else
      {ast, issues}
    end
  end

  defp traverse(ast, issues, _issue_meta), do: {ast, issues}

  defp clause_pattern({:->, _, [[pattern], _body]}), do: pattern
  defp clause_pattern(_), do: :no_match

  defp plain_variable?({name, _meta, ctx}) when is_atom(name) and is_atom(ctx), do: true
  defp plain_variable?(_), do: false

  defp boolean_clause_pair?(a, b) do
    case {normalize_pattern(a), normalize_pattern(b)} do
      {true, false} -> true
      {false, true} -> true
      {true, :wildcard} -> true
      {:wildcard, true} -> true
      {false, :wildcard} -> true
      {:wildcard, false} -> true
      _ -> false
    end
  end

  defp normalize_pattern(true), do: true
  defp normalize_pattern(false), do: false
  defp normalize_pattern({:_, _, _}), do: :wildcard
  defp normalize_pattern(_), do: :other
end
