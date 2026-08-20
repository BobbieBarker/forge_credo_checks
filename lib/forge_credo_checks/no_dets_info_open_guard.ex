defmodule ForgeCredoChecks.NoDetsInfoOpenGuard do
  use Credo.Check,
    base_priority: :high,
    category: :warning,
    explanations: [
      check: """
      Call `:dets.open_file/2` unconditionally. Never gate it on `:dets.info/1`.

      ## Why

      `:dets.open_file/2` registers the calling process as a `dets_server` user
      of the table. `:dets.info/1` does not — it is a plain registry read that
      reports whether *someone* has the table open, not whether *you* do.

      A caller that skips `open_file` because `info` said the table was already
      open therefore never becomes a registered user. Data operations keep
      working while the process that did register stays alive, so the bug is
      invisible in a single-caller test. As soon as that process closes the
      table, `dets_server`'s `handle_close/4` deletes the registry row
      synchronously and the unregistered caller's next write raises — far from
      the guard that caused it, and only under the interleaving that closes
      first.

      `:dets.open_file/2` against an already-open table is cheap and idempotent
      for a registered user, so the guard buys nothing.

      ## Bad

          # Registry read used as a guard: this caller is never registered.
          if :dets.info(table) !== :undefined do
            {:ok, table}
          else
            :dets.open_file(table, file: path, type: :set)
          end

          case :dets.info(table) do
            :undefined -> :dets.open_file(table, file: path, type: :set)
            _ -> {:ok, table}
          end

          # Binding the result first changes nothing. Also flagged.
          info = :dets.info(table)
          if info === :undefined, do: :dets.open_file(table, opts), else: {:ok, table}

      ## Good

          # Open unconditionally and treat an already-open table as success.
          # Every caller that runs this is a registered dets_server user.
          case :dets.open_file(table, file: path, type: :set) do
            {:ok, ^table} -> {:ok, table}
            {:error, {:already_started, ^table}} -> {:ok, table}
            {:error, reason} -> {:error, reason}
          end

      Deleting the comparison and calling `:dets.info/1` for its side effect is
      not a fix — `info` never registers the caller no matter how its result is
      used. The registering call is `open_file`, and it has to actually run.

      ## What is flagged

      Inside `lib/` source files, an arity-1 `:dets.info(table)` compared
      against `:undefined`: as an operand of `===`, `!==`, `==`, or `!=` in
      either position, or as a `case` subject with an `:undefined` clause.

      A variable bound exactly once to `:dets.info/1` in the enclosing function
      body counts as the call itself, so lifting the call into a binding does
      not evade the check. A name assigned more than once is not tracked, and a
      binding never leaks into a sibling function body.

      ## Not flagged

        * `:dets.info(table, :size)` and other arity-2 calls — legitimate
          size/metadata queries that do not gate `open_file`.
        * Comparisons of `:dets.info/1` against anything but `:undefined`.
        * Test files: the stale-registry hazard is production-only.
      """
    ]

  alias Credo.{Code, IssueMeta}

  @comparison_ops [:===, :!==, :==, :!=]

  @doc false
  @spec run(Credo.SourceFile.t(), keyword()) :: [Credo.Issue.t()]
  def run(%{filename: filename} = source_file, params \\ []) do
    if lib_file?(filename) do
      issue_meta = IssueMeta.for(source_file, params)

      {issues, _bindings} =
        Code.prewalk(source_file, &traverse(&1, &2, issue_meta), {[], MapSet.new()})

      issues
    else
      []
    end
  end

  defp lib_file?(filename) when is_binary(filename) do
    filename
    |> Path.split()
    |> Enum.any?(&(&1 === "lib"))
  end

  defp lib_file?(_filename), do: false

  # A function body opens a fresh binding scope: the names it binds to an
  # `:dets.info/1` result are meaningful only inside it, and must not leak into
  # a sibling clause that happens to reuse the name.
  defp traverse({def_kind, _meta, [_head, body]} = ast, {issues, _bindings}, _issue_meta)
       when def_kind in [:def, :defp] and is_list(body) do
    {ast, {issues, info_bindings(body)}}
  end

  defp traverse(
         {:case, meta, [subject, [do: clauses]]} = ast,
         {issues, bindings} = acc,
         issue_meta
       ) do
    if info_expression?(subject, bindings) and case_matches_undefined?(clauses) do
      {ast,
       {[issue_for(issue_meta, ":dets.info/1", Keyword.get(meta, :line)) | issues], bindings}}
    else
      {ast, acc}
    end
  end

  defp traverse({op, meta, [left, right]} = ast, {issues, bindings} = acc, issue_meta)
       when op in @comparison_ops do
    if open_guard?(left, right, bindings) or open_guard?(right, left, bindings) do
      {ast,
       {[issue_for(issue_meta, ":dets.info/1", Keyword.get(meta, :line)) | issues], bindings}}
    else
      {ast, acc}
    end
  end

  defp traverse(ast, acc, _issue_meta), do: {ast, acc}

  defp open_guard?(info_side, other_side, bindings) do
    info_expression?(info_side, bindings) and undefined_literal?(other_side)
  end

  # Either the `:dets.info/1` call itself, or a variable standing in for it.
  # Binding the result first is the most natural edit an agent makes when told
  # the comparison is the problem, and it changes nothing about the hazard.
  defp info_expression?(ast, bindings) do
    arity1_dets_info?(ast) or bound_info_variable?(ast, bindings)
  end

  defp bound_info_variable?({name, _meta, context}, bindings)
       when is_atom(name) and is_atom(context) do
    MapSet.member?(bindings, name)
  end

  defp bound_info_variable?(_ast, _bindings), do: false

  # Names this body binds exactly once, to an arity-1 `:dets.info/1` call. A
  # name assigned more than once is dropped: the later value is something else,
  # and the check has no flow analysis to tell which one a comparison sees.
  defp info_bindings(body) do
    {_body, assignments} = Macro.prewalk(body, %{}, &collect_assignment/2)

    for {name, [value]} <- assignments, arity1_dets_info?(value), into: MapSet.new(), do: name
  end

  defp collect_assignment({:=, _meta, [{name, _var_meta, context}, value]} = ast, assignments)
       when is_atom(name) and is_atom(context) do
    {ast, Map.update(assignments, name, [value], &[value | &1])}
  end

  defp collect_assignment(ast, assignments), do: {ast, assignments}

  defp case_matches_undefined?(clauses) do
    Enum.any?(clauses, &undefined_case_clause?/1)
  end

  defp undefined_case_clause?({:->, _meta, [patterns, _body]}) when is_list(patterns) do
    Enum.any?(patterns, &undefined_case_pattern?/1)
  end

  defp undefined_case_clause?(_clause), do: false

  defp undefined_case_pattern?({:when, _meta, [pattern | _guards]}),
    do: undefined_case_pattern?(pattern)

  defp undefined_case_pattern?(pattern), do: undefined_literal?(pattern)

  defp arity1_dets_info?({{:., _dot_meta, [:dets, :info]}, _call_meta, [_arg]}), do: true
  defp arity1_dets_info?(_other), do: false

  defp undefined_literal?(:undefined), do: true
  defp undefined_literal?(_other), do: false

  defp issue_for(issue_meta, trigger, line_no) do
    format_issue(issue_meta,
      message: """
      :dets.info/1 used as an open-file guard does not register the caller as a \
      dets_server user. Call :dets.open_file/2 unconditionally and match \
      {:already_started, _} instead.
      """,
      trigger: trigger,
      line_no: line_no
    )
  end
end
