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

          # Bad -- the error message has a hardcoded string, no failing args
          def parse(_), do: raise(ArgumentError, "expected a list")

          # Good -- remove the catch-all. The FunctionClauseError will say:
          #   "no function clause matching in parse/1
          #    with args: (42)"

      LLMs generate these defensively because their training data is full of
      Python/Java patterns where unhandled cases must raise explicitly. In
      Elixir, let the non-match crash naturally.

      ## Flagged

      A `def`/`defp` clause where:

      1. Every argument is a wildcard (`_` or a `_name`), AND
      2. The body is exactly one `raise(...)` call, AND
      3. At least one other clause exists for the same `{name, arity}`
         within the same module.

      Guarded clauses are not flagged -- the guard implies intentional logic.

      ## Not flagged

      - Catch-alls that return a value (`{:error, :invalid}`)
      - Clauses that log or clean up before raising
      - Zero-arity functions
      - Single-clause functions that raise (stubs, arity redirects,
        deliberately-raising test doubles). These are not "catch-alls"
        because there is no other clause to fall through from.

      ## How to fix

      Consider whether the raise message adds information beyond what
      `FunctionClauseError` already provides:

      - If not, remove the clause entirely.
      - If the message documents valid inputs or redirects to another
        arity, consider narrowing the guard instead of using all-wildcards,
        or keep the clause and disable this check inline.

      To exclude test files, add to `.credo.exs`:

          {ForgeCredoChecks.NoUnnecessaryCatchAllRaise,
           files: %{excluded: [~r"_test\\.exs$", ~r"test/support/"]}}
      """
    ]

  alias Credo.SourceFile

  @doc false
  def run(source_file, params \\ []) do
    issue_meta = IssueMeta.for(source_file, params)
    ast = SourceFile.ast(source_file)

    clauses = collect_clauses(ast)

    clause_counts =
      Enum.frequencies_by(clauses, fn {mod, name, arity, _meta, _def_type, _raises?} ->
        {mod, name, arity}
      end)

    clauses
    |> Enum.filter(fn {mod, name, arity, _meta, _def_type, raises?} ->
      raises? and Map.get(clause_counts, {mod, name, arity}, 0) >= 2
    end)
    |> Enum.map(fn {_mod, name, arity, meta, def_type, _raises?} ->
      format_issue(issue_meta,
        message:
          "Catch-all clause in `#{def_type} #{name}/#{arity}` raises with a " <>
            "hardcoded message. `FunctionClauseError` already provides the " <>
            "function name and actual failing arguments. Consider removing " <>
            "this clause, or narrowing the guard if the raise message documents " <>
            "valid inputs.",
        trigger: Atom.to_string(name),
        line_no: Keyword.get(meta, :line)
      )
    end)
  end

  defp collect_clauses(ast) do
    {_ast, %{clauses: clauses}} =
      Macro.traverse(ast, %{clauses: [], module_stack: []}, &pre/2, &post/2)

    Enum.reverse(clauses)
  end

  defp pre({mod_type, meta, [{:__aliases__, _, _} | _]} = node, acc)
       when mod_type in [:defmodule, :defimpl, :defprotocol] do
    scope_id = {mod_type, Keyword.get(meta, :line)}
    {node, %{acc | module_stack: [scope_id | acc.module_stack]}}
  end

  defp pre(node, acc) do
    case extract_clause(node, acc.module_stack) do
      {:ok, clause} -> {node, %{acc | clauses: [clause | acc.clauses]}}
      :error -> {node, acc}
    end
  end

  defp post(
         {mod_type, _meta, [{:__aliases__, _, _} | _]} = node,
         %{module_stack: [_ | rest]} = acc
       )
       when mod_type in [:defmodule, :defimpl, :defprotocol] do
    {node, %{acc | module_stack: rest}}
  end

  defp post(node, acc), do: {node, acc}

  defp extract_clause(
         {def_type, meta, [{:when, _, [{fn_name, _, args}, _guard]}, _body]},
         mod_stack
       )
       when def_type in [:def, :defp] and is_atom(fn_name) and is_list(args) do
    {:ok, {mod_stack, fn_name, length(args), meta, def_type, false}}
  end

  defp extract_clause({def_type, meta, [{fn_name, _, args}, body]}, mod_stack)
       when def_type in [:def, :defp] and is_atom(fn_name) and is_list(args) do
    raises? = all_wildcards?(args) and body_only_raises?(body)
    {:ok, {mod_stack, fn_name, length(args), meta, def_type, raises?}}
  end

  defp extract_clause(_, _), do: :error

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
