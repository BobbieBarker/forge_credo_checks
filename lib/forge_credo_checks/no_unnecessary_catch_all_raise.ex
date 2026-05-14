defmodule ForgeCredoChecks.NoUnnecessaryCatchAllRaise do
  use Credo.Check,
    base_priority: :high,
    category: :refactor,
    explanations: [
      check: """
      Catch-all clauses that only `raise` discard Elixir's built-in diagnostics.

      ## Why

      Elixir's `FunctionClauseError` already names the function AND shows the
      actual arguments that failed to match. That is the best diagnostic you
      can give to a debugger. A hand-written catch-all that raises a generic
      error throws that signal away:

          # Bad — the error message has a hardcoded string, no failing args
          def parse(_), do: raise(ArgumentError, "expected a list")

          # Good — remove the catch-all. The FunctionClauseError will say:
          #   "no function clause matching in parse/1
          #    with args: (42)"

      LLMs generate these defensively because their training data is full of
      Python/Java patterns where unhandled cases must raise explicitly. In
      Elixir, let the non-match crash naturally.

      ## Flagged

      A `def`/`defp` clause where:

      1. Every argument is a wildcard (`_` or a `_name`), AND
      2. The body is exactly one `raise(...)` call.

      Guarded clauses are not flagged — the guard implies intentional logic.

      ## Not flagged

      - Catch-alls that return a value (`{:error, :invalid}`)
      - Clauses that log or clean up before raising
      - Zero-arity functions
      """
    ]

  @doc false
  def run(source_file, params \\ []) do
    issue_meta = IssueMeta.for(source_file, params)
    Credo.Code.prewalk(source_file, &traverse(&1, &2, issue_meta))
  end

  defp traverse({def_type, meta, [{fn_name, _, args}, body]} = ast, issues, issue_meta)
       when def_type in [:def, :defp] and is_atom(fn_name) and is_list(args) do
    if all_wildcards?(args) and body_only_raises?(body) do
      issue =
        format_issue(issue_meta,
          message:
            "Unnecessary catch-all clause in `#{def_type} #{fn_name}/#{length(args)}`. " <>
              "Elixir raises `FunctionClauseError` automatically on unmatched calls — " <>
              "with the actual failing arguments, which a hardcoded `raise` cannot " <>
              "provide. Remove this clause and rely on the built-in diagnostic.",
          trigger: Atom.to_string(fn_name),
          line_no: Keyword.get(meta, :line)
        )

      {ast, [issue | issues]}
    else
      {ast, issues}
    end
  end

  defp traverse(ast, issues, _issue_meta), do: {ast, issues}

  defp all_wildcards?([]), do: false
  defp all_wildcards?(args), do: Enum.all?(args, &wildcard?/1)

  defp wildcard?({:_, _, ctx}) when is_atom(ctx), do: true

  defp wildcard?({name, _, ctx}) when is_atom(name) and is_atom(ctx) do
    name |> Atom.to_string() |> String.starts_with?("_")
  end

  defp wildcard?(_), do: false

  defp body_only_raises?(do: {:raise, _, _}), do: true
  defp body_only_raises?(_), do: false
end
