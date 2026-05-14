defmodule ForgeCredoChecks.InconsistentParamNames do
  use Credo.Check,
    base_priority: :high,
    category: :readability,
    explanations: [
      check: """
      Parameter names should match across clauses of the same function.

      ## Why

      LLMs write function clauses semi-independently and let the parameter
      names drift between them:

          # Flagged — position 1 is `current` in one clause, `prev` in another
          defp do_fib(current, _next, 0), do: current
          defp do_fib(prev, current, steps), do: do_fib(current, prev + current, steps - 1)

          # Consistent
          defp do_fib(prev, _current, 0), do: prev
          defp do_fib(prev, current, steps), do: do_fib(current, prev + current, steps - 1)

      Drift makes readers question correctness: if position 1 is `current`
      in one clause and `prev` in another, which is the real intent?

      ## Detection

      Clauses of the same `{name, arity}` are grouped. For each positional
      argument, base names (with any leading `_` stripped) are compared
      across clauses; differences flag.

      Positions where any clause uses a literal, tuple/list pattern, or bare
      `_` are skipped — destructuring is intentional pattern matching, not
      a parameter name.
      """
    ]

  alias Credo.SourceFile

  @doc false
  def run(source_file, params \\ []) do
    issue_meta = IssueMeta.for(source_file, params)
    ast = SourceFile.ast(source_file)

    ast
    |> collect_clauses()
    |> Enum.group_by(fn {name, arity, _args, _meta, _def_type} -> {name, arity} end)
    |> Enum.flat_map(fn {_key, group} -> analyze_group(group, issue_meta) end)
    |> Enum.sort_by(& &1.line_no)
  end

  defp collect_clauses(ast) do
    {_ast, clauses} =
      Macro.prewalk(ast, [], fn node, acc ->
        case extract_clause_info(node) do
          {:ok, clause} -> {node, [clause | acc]}
          :error -> {node, acc}
        end
      end)

    Enum.reverse(clauses)
  end

  defp extract_clause_info({def_type, meta, [{:when, _, [{fn_name, _, args}, _guard]}, _body]})
       when def_type in [:def, :defp] and is_atom(fn_name) and is_list(args) do
    {:ok, {fn_name, length(args), args, meta, def_type}}
  end

  defp extract_clause_info({def_type, meta, [{fn_name, _, args}, _body]})
       when def_type in [:def, :defp] and is_atom(fn_name) and is_list(args) do
    {:ok, {fn_name, length(args), args, meta, def_type}}
  end

  defp extract_clause_info(_), do: :error

  defp analyze_group(clauses, _issue_meta) when length(clauses) < 2, do: []

  defp analyze_group(clauses, issue_meta) do
    [{name, arity, _, _, def_type} | _] = clauses
    args_lists = Enum.map(clauses, fn {_, _, args, _, _} -> args end)
    metas = Enum.map(clauses, fn {_, _, _, meta, _} -> meta end)

    Enum.flat_map(0..(arity - 1), fn pos ->
      bases =
        args_lists
        |> Enum.map(fn args -> Enum.at(args, pos) end)
        |> Enum.map(&extract_base_name/1)

      issues_for_position(bases, metas, pos, name, arity, def_type, issue_meta)
    end)
  end

  defp issues_for_position(bases, _metas, _pos, _name, _arity, _def_type, _issue_meta)
       when bases == [] or hd(bases) == nil,
       do: []

  defp issues_for_position(bases, metas, pos, name, arity, def_type, issue_meta) do
    cond do
      Enum.any?(bases, &is_nil/1) ->
        []

      match?([_], Enum.uniq(bases)) ->
        []

      true ->
        line = first_drift_line(bases, metas)
        unique_bases = Enum.uniq(bases)
        [build_issue(issue_meta, def_type, name, arity, pos + 1, unique_bases, line)]
    end
  end

  defp first_drift_line(bases, metas) do
    [first | _] = bases

    bases
    |> Enum.zip(metas)
    |> Enum.find_value(fn {base, meta} ->
      if base != first, do: Keyword.get(meta, :line)
    end) || metas |> hd() |> Keyword.get(:line)
  end

  defp extract_base_name({name, _, ctx}) when is_atom(name) and is_atom(ctx) do
    base_name_of_atom(name)
  end

  defp extract_base_name(_), do: nil

  defp base_name_of_atom(name) do
    str = Atom.to_string(name)

    cond do
      str == "_" -> nil
      String.starts_with?(str, "_") -> String.trim_leading(str, "_")
      true -> str
    end
  end

  defp build_issue(issue_meta, def_type, name, arity, position, conflicting, line) do
    names_str = Enum.map_join(conflicting, ", ", &"`#{&1}`")

    format_issue(issue_meta,
      message:
        "Inconsistent parameter names in `#{def_type} #{name}/#{arity}` at position " <>
          "#{position}: #{names_str}. Pick one base name and use it consistently across " <>
          "clauses, or use `_` to mark the parameter unused in a clause.",
      trigger: Atom.to_string(name),
      line_no: line
    )
  end
end
