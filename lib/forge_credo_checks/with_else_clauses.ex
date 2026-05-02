defmodule ForgeCredoChecks.WithElseClauses do
  use Credo.Check,
    base_priority: :normal,
    category: :refactor,
    param_defaults: [max_clauses: 1],
    explanations: [
      check: """
      Avoid wide `else` blocks on `with` expressions.

      ## Why

      All failure clauses from every `<-` step are flattened into a single
      `else` block. The block stops describing which step failed and
      becomes a dispatch table on error shapes - and an exhaustive one,
      since any unmatched failure raises `WithClauseError`.

      Prefer letting non-matches fall through: if every `<-` step returns a
      uniform shape (`:ok | {:error, reason}` or `{:ok, value} | {:error, reason}`),
      the bare `with` (no `else`) returns the first error verbatim and the
      caller decides what to do.

      ## How to fix

      For each `<-` step that returns a step-specific shape, wrap the call
      in a private helper that returns the uniform shape. Then delete the
      `else` block.

          # BEFORE - else dispatches on step-specific shapes
          with {:ok, user} <- Repo.get(User, id) |> ok_or_nil(),
               true <- User.active?(user) do
            {:ok, user}
          else
            nil -> {:error, :not_found}
            false -> {:error, :inactive}
            {:error, _} = err -> err
          end

          # AFTER - each step returns {:ok, _} | {:error, _}; no else needed
          with {:ok, user} <- find_user(id),
               :ok <- ensure_active(user) do
            {:ok, user}
          end

          defp find_user(id) do
            case Repo.get(User, id) do
              nil -> {:error, :not_found}
              user -> {:ok, user}
            end
          end

          defp ensure_active(user) do
            if User.active?(user), do: :ok, else: {:error, :inactive}
          end

      ## What NOT to do

      Do not collapse the `else` into a single catch-all clause to silence
      this check - that loses the per-step error context entirely:

          # STILL BAD
          else
            err -> {:error, err}
          end

      Push the normalization upstream into helpers, as shown above.

      ## Configuration

      This check fires when a `with` has more than `:max_clauses` `else`
      clauses (default `1`). Set `:max_clauses` to `0` to forbid `else`
      entirely; raise it for codebases that accept wider blocks.
      """,
      params: [
        max_clauses:
          "Maximum number of `else` clauses allowed before the check fires. Default: `1`."
      ]
    ]

  @doc false
  def run(source_file, params \\ []) do
    issue_meta = IssueMeta.for(source_file, params)
    max_clauses = Params.get(params, :max_clauses, __MODULE__)
    Credo.Code.prewalk(source_file, &traverse(&1, &2, issue_meta, max_clauses))
  end

  defp traverse({:with, meta, args} = ast, issues, issue_meta, max_clauses)
       when is_list(args) do
    case else_clause_count(args) do
      count when count > max_clauses ->
        {ast, issues ++ [issue_for(issue_meta, meta[:line], count, max_clauses)]}

      _ ->
        {ast, issues}
    end
  end

  defp traverse(ast, issues, _issue_meta, _max_clauses), do: {ast, issues}

  defp else_clause_count(args) do
    case List.last(args) do
      kw when is_list(kw) ->
        case Keyword.get(kw, :else) do
          clauses when is_list(clauses) -> length(clauses)
          _ -> 0
        end

      _ ->
        0
    end
  end

  defp issue_for(issue_meta, line_no, count, max) do
    format_issue(issue_meta,
      message:
        "`with` has #{count} `else` #{pluralize(count)} (max: #{max}). " <>
          "Fix: for each `<-` step whose failure is matched in `else`, wrap that " <>
          "call in a private helper that returns a uniform `:ok | {:error, reason}` " <>
          "(or `{:ok, value} | {:error, reason}`) shape, then delete the `else` block " <>
          "so non-matches fall through. Do NOT collapse `else` to a catch-all - " <>
          "push the normalization upstream into helpers. " <>
          "Or raise `:max_clauses` in `.credo.exs` if this codebase accepts wider blocks.",
      trigger: "else",
      line_no: line_no
    )
  end

  defp pluralize(1), do: "clause"
  defp pluralize(_), do: "clauses"
end
