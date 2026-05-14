defmodule ForgeCredoChecks.NoKernelShadowing do
  use Credo.Check,
    base_priority: :high,
    category: :readability,
    explanations: [
      check: """
      Variable names that shadow common Kernel functions hurt readability.

      ## Why

      Naming a variable `max` shadows `Kernel.max/2`. Code like
      `max(max, other)` becomes ambiguous to readers and to lexical-grep
      tools: is `max` a function call being shadowed, or the variable?

      LLMs frequently generate this in `Enum.reduce/3` accumulators or
      function arguments because the name is the obvious one for the value.

      ## Bad

          Enum.reduce(list, 0, fn x, max -> max(max, x) end)

          defp longest(strings, max), do: ...

      ## Good

          Enum.reduce(list, 0, fn x, current_max -> max(current_max, x) end)

          defp longest(strings, max_length), do: ...

      ## Names flagged

      `max`, `min`, `elem`, `hd`, `tl`, `length`, `abs`, `round`, `trunc`,
      `div`, `rem`, `tuple_size`, `map_size`, `byte_size`, `bit_size`.

      Only binding sites are checked: `=` LHS, `fn` parameters, `def`/`defp`
      parameters. References after the binding (e.g. `max(max, x)`) are not
      flagged on their own — the binding is the root cause.
      """
    ]

  @shadowed [
    :max,
    :min,
    :elem,
    :hd,
    :tl,
    :length,
    :abs,
    :round,
    :trunc,
    :div,
    :rem,
    :tuple_size,
    :map_size,
    :byte_size,
    :bit_size
  ]

  @doc false
  def run(source_file, params \\ []) do
    issue_meta = IssueMeta.for(source_file, params)
    Credo.Code.prewalk(source_file, &traverse(&1, &2, issue_meta))
  end

  defp traverse({:=, meta, [lhs, _rhs]} = ast, issues, issue_meta) do
    {ast, issues_in(lhs, meta, issue_meta) ++ issues}
  end

  defp traverse({:fn, _meta, clauses} = ast, issues, issue_meta) do
    new =
      Enum.flat_map(clauses, fn
        {:->, meta, [params, _body]} ->
          Enum.flat_map(params, &issues_in(&1, meta, issue_meta))

        _ ->
          []
      end)

    {ast, new ++ issues}
  end

  defp traverse({def_type, _meta, [{_name, head_meta, args}, _body]} = ast, issues, issue_meta)
       when def_type in [:def, :defp] and is_list(args) do
    new = Enum.flat_map(args, &issues_in(&1, head_meta, issue_meta))
    {ast, new ++ issues}
  end

  defp traverse(ast, issues, _issue_meta), do: {ast, issues}

  defp issues_in(node, fallback_meta, issue_meta) do
    {_, acc} =
      Macro.prewalk(node, [], fn
        {name, var_meta, ctx} = inner, acc when name in @shadowed and is_atom(ctx) ->
          line =
            Keyword.get(var_meta || [], :line) ||
              Keyword.get(fallback_meta || [], :line)

          issue =
            format_issue(issue_meta,
              message:
                "Variable `#{name}` shadows `Kernel.#{name}`. Calls like " <>
                  "`#{name}(#{name}, other)` become ambiguous to readers. " <>
                  "Rename to `#{name}_value`, `current_#{name}`, or similar.",
              trigger: Atom.to_string(name),
              line_no: line
            )

          {inner, [issue | acc]}

        node, acc ->
          {node, acc}
      end)

    acc
  end
end
