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

          # Flagged -- position 1 is `current` in one clause, `prev` in another
          defp do_fib(current, _next, 0), do: current
          defp do_fib(prev, current, steps), do: do_fib(current, prev + current, steps - 1)

          # Consistent
          defp do_fib(prev, _current, 0), do: prev
          defp do_fib(prev, current, steps), do: do_fib(current, prev + current, steps - 1)

      Drift makes readers question correctness: if position 1 is `current`
      in one clause and `prev` in another, which is the real intent?

      ## Detection

      Clauses of the same `{name, arity}` within the same module are grouped.
      For each positional argument, base names (with any leading `_` stripped)
      are compared across clauses; differences flag.

      Clauses in different `defmodule`, `defimpl`, or `defprotocol` blocks
      are never compared, even if they share a function name and arity.
      Protocol implementations idiomatically name parameters after the
      implementing type, so cross-impl comparison would be a false positive.

      Positions where any clause uses a literal, tuple/list pattern, or bare
      `_` are skipped -- destructuring is intentional pattern matching, not
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
    |> Enum.group_by(fn {mod, name, arity, _args, _meta, _def_type} -> {mod, name, arity} end)
    |> Enum.flat_map(fn {_key, group} -> analyze_group(group, issue_meta) end)
    |> Enum.sort_by(& &1.line_no)
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
    case extract_clause_info(node, acc.module_stack) do
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

  defp extract_clause_info(
         {def_type, meta, [{:when, _, [{fn_name, _, args}, _guard]}, _body]},
         mod_stack
       )
       when def_type in [:def, :defp] and is_atom(fn_name) and is_list(args) do
    {:ok, {mod_stack, fn_name, length(args), args, meta, def_type}}
  end

  defp extract_clause_info({def_type, meta, [{fn_name, _, args}, _body]}, mod_stack)
       when def_type in [:def, :defp] and is_atom(fn_name) and is_list(args) do
    {:ok, {mod_stack, fn_name, length(args), args, meta, def_type}}
  end

  defp extract_clause_info(_, _), do: :error

  defp analyze_group(clauses, _issue_meta) when length(clauses) < 2, do: []

  defp analyze_group(clauses, issue_meta) do
    [{_, name, arity, _, _, def_type} | _] = clauses
    args_lists = Enum.map(clauses, fn {_, _, _, args, _, _} -> args end)

    inconsistent_positions =
      Enum.flat_map(0..(arity - 1), fn pos ->
        bases =
          args_lists
          |> Enum.map(fn args -> Enum.at(args, pos) end)
          |> Enum.map(&extract_base_name/1)

        case position_conflict(bases) do
          {:conflict, unique_bases} -> [{pos + 1, unique_bases}]
          :ok -> []
        end
      end)

    case inconsistent_positions do
      [] ->
        []

      positions ->
        [build_issue(issue_meta, def_type, name, arity, positions, first_drift_line(clauses))]
    end
  end

  defp position_conflict(bases) do
    cond do
      Enum.any?(bases, &is_nil/1) -> :ok
      match?([_], Enum.uniq(bases)) -> :ok
      true -> {:conflict, Enum.uniq(bases)}
    end
  end

  defp first_drift_line(clauses) do
    [{_, _, _, _, first_meta, _} | rest] = clauses

    Enum.find_value(rest, fn {_, _, _, _, meta, _} ->
      Keyword.get(meta, :line)
    end) || Keyword.get(first_meta, :line)
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

  defp build_issue(issue_meta, def_type, name, arity, positions, line) do
    positions_str =
      Enum.map_join(positions, "; ", fn {pos, conflicting} ->
        names = Enum.map_join(conflicting, ", ", &"`#{&1}`")
        "position #{pos}: #{names}"
      end)

    format_issue(issue_meta,
      message:
        "Inconsistent parameter names in `#{def_type} #{name}/#{arity}`: " <>
          "#{positions_str}. Pick one base name per position and use it " <>
          "consistently across clauses, or use `_` to mark unused parameters.",
      trigger: Atom.to_string(name),
      line_no: line
    )
  end
end
