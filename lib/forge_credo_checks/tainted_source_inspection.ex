defmodule ForgeCredoChecks.TaintedSourceInspection do
  @moduledoc """
  Flags source-grep checks against source text read from non-test Elixir files.
  """

  use Credo.Check,
    base_priority: :high,
    category: :warning,
    param_defaults: [excluded_paths: []],
    explanations: [
      check: """
      Source-grep tests must be replaced with behavioural contract tests.

      ## Why

      Reading a non-test `.ex` / `.exs` file and then searching its text with
      `=~`, `String.contains?`, `Regex.*`, or `Code.eval_string` proves only that
      a spelling exists. It does not prove the code path works, and it breaks on
      behaviour-preserving refactors.

      Use contract coverage instead: call the public producer/consumer API and
      assert the returned value or effect. For the Forge/Anubis migration, the
      reference pattern lives in `contracts/template_variables_contract_test.exs`.

      ## What is flagged

      This check flags source-grep constructs applied to values tainted from
      `File.read!` or `File.stream!` of a path literal that is not under `test/`
      and ends in `.ex` or `.exs`. Taint is tracked through simple in-file
      bindings, module attributes, pipes, and common enumerable callbacks.

      Terminal artifact reads are intentionally outside this check. Reading
      `.md`, `.txt`, `.yml`, `.yaml`, `doc/`, or `docs/` artifacts remains quiet,
      even when the artifact text is searched.

      ## Configuration

      `excluded_paths` is a list of patterns (regexes or substrings) matched
      against each file's path; a matching file is skipped. Use it only as a
      shrinking migration bridge while replacing source-grep tests with contract
      tests:

          {ForgeCredoChecks.TaintedSourceInspection,
           excluded_paths: [~r"^test/legacy_source_grep/"]}
      """,
      params: [
        excluded_paths: "Paths skipped entirely (regexes or substrings)."
      ]
    ]

  @contract_path "contracts/template_variables_contract_test.exs"
  @def_forms [:def, :defp, :defmacro, :defmacrop]
  @enum_modules [:Enum, :Stream]
  @source_extensions [".ex", ".exs"]
  @source_readers [:read!, :stream!]
  @terminal_artifact_extensions [".md", ".txt", ".yml", ".yaml"]

  @doc false
  def run(source_file, params \\ []) do
    if excluded_path?(source_file, params) do
      []
    else
      issue_meta = IssueMeta.for(source_file, params)

      source_file
      |> Credo.SourceFile.ast()
      |> analyze(initial_state(issue_meta))
      |> elem(1)
      |> Map.fetch!(:issues)
      |> Enum.reverse()
    end
  end

  defp excluded_path?(%{filename: filename}, params) when is_binary(filename) do
    params
    |> Params.get(:excluded_paths, __MODULE__)
    |> Enum.any?(&(filename =~ &1))
  end

  defp excluded_path?(_source_file, _params), do: false

  defp initial_state(issue_meta) do
    %{
      issue_meta: issue_meta,
      issues: [],
      source_path_attrs: MapSet.new(),
      source_path_vars: MapSet.new(),
      tainted_attrs: MapSet.new(),
      tainted_captures: MapSet.new(),
      tainted_vars: MapSet.new()
    }
  end

  defp analyze(ast, state) do
    ast
    |> flag_sink(state)
    |> do_analyze(ast)
  end

  defp do_analyze(state, {:__block__, _meta, expressions}) when is_list(expressions) do
    analyze_block(expressions, state)
  end

  defp do_analyze(state, {:=, _meta, [lhs, rhs]}) do
    {_tainted, state} = analyze(rhs, state)
    tainted? = tainted_expr?(rhs, state)
    source_path? = source_path_expr?(rhs, state)

    {tainted?, bind_pattern(lhs, tainted?, source_path?, state)}
  end

  defp do_analyze(state, {:@, _meta, [{name, _attr_meta, [value]}]})
       when is_atom(name) do
    {_tainted, state} = analyze(value, state)
    tainted? = tainted_expr?(value, state)
    source_path? = source_path_expr?(value, state)

    {tainted?, bind_attr(name, tainted?, source_path?, state)}
  end

  defp do_analyze(state, {:@, _meta, [{name, _attr_meta, nil}]}) when is_atom(name) do
    {MapSet.member?(state.tainted_attrs, name), state}
  end

  defp do_analyze(state, {:defmodule, _meta, [_module, [do: body]]}) do
    scoped = %{
      state
      | source_path_attrs: MapSet.new(),
        source_path_vars: MapSet.new(),
        tainted_attrs: MapSet.new(),
        tainted_captures: MapSet.new(),
        tainted_vars: MapSet.new()
    }

    {_tainted, scoped} = analyze(body, scoped)
    {false, %{state | issues: scoped.issues}}
  end

  defp do_analyze(state, {form, _meta, [_head, body]})
       when form in @def_forms and is_list(body) do
    case Keyword.fetch(body, :do) do
      {:ok, do_block} ->
        analyze_function_body(do_block, state)

      :error ->
        {false, state}
    end
  end

  defp do_analyze(state, {:fn, _meta, clauses}) when is_list(clauses) do
    {false, Enum.reduce(clauses, state, &analyze_clean_callback_clause/2)}
  end

  defp do_analyze(state, {:for, _meta, clauses}) when is_list(clauses) do
    analyze_for(clauses, state)
  end

  defp do_analyze(state, {:|>, _meta, [lhs, rhs]} = ast) do
    {_tainted, state} = analyze(lhs, state)
    state = analyze_piped_callback(lhs, rhs, state)
    {_tainted, state} = analyze(rhs, state)

    {tainted_expr?(ast, state), state}
  end

  defp do_analyze(
         state,
         {{:., _dot_meta, [{:__aliases__, _alias_meta, [module]}, _fun]}, _meta, args} = ast
       )
       when module in @enum_modules and is_list(args) do
    state = analyze_enum_callback(args, state)
    {_tainted, state} = analyze_children(Tuple.to_list(ast), state)

    {tainted_expr?(ast, state), state}
  end

  defp do_analyze(state, tuple) when is_tuple(tuple) do
    {_tainted, state} = analyze_children(Tuple.to_list(tuple), state)
    {tainted_expr?(tuple, state), state}
  end

  defp do_analyze(state, list) when is_list(list) do
    analyze_children(list, state)
  end

  defp do_analyze(state, literal), do: {tainted_expr?(literal, state), state}

  defp analyze_block(expressions, state) do
    Enum.reduce(expressions, {false, state}, fn expression, {_last_tainted, state} ->
      analyze(expression, state)
    end)
  end

  defp analyze_children(children, state) do
    Enum.reduce(children, {false, state}, fn child, {_last_tainted, state} ->
      analyze(child, state)
    end)
  end

  defp analyze_function_body(body, state) do
    scoped = %{
      state
      | source_path_vars: MapSet.new(),
        tainted_captures: MapSet.new(),
        tainted_vars: MapSet.new()
    }

    {_tainted, scoped} = analyze(body, scoped)
    {false, %{state | issues: scoped.issues}}
  end

  defp analyze_for(clauses, state) do
    {body, qualifiers} = pop_do(clauses)
    scoped = %{state | tainted_captures: MapSet.new()}

    scoped =
      Enum.reduce(qualifiers, scoped, fn
        {:<-, _meta, [pattern, enumerable]}, scoped ->
          {_tainted, scoped} = analyze(enumerable, scoped)
          bind_pattern(pattern, tainted_expr?(enumerable, scoped), false, scoped)

        qualifier, scoped ->
          {_tainted, scoped} = analyze(qualifier, scoped)
          scoped
      end)

    {_tainted, scoped} = analyze(body, scoped)
    {false, %{state | issues: scoped.issues}}
  end

  defp pop_do(clauses) do
    {keyword, qualifiers} = Enum.split_with(clauses, &match?({key, _value} when is_atom(key), &1))

    case Keyword.fetch(keyword, :do) do
      {:ok, body} -> {body, qualifiers}
      :error -> {nil, qualifiers}
    end
  end

  defp analyze_enum_callback([enumerable | callback_args], state) do
    if tainted_expr?(enumerable, state) do
      callback_args
      |> Enum.find(&callback?/1)
      |> analyze_callback(state)
    else
      state
    end
  end

  defp analyze_enum_callback(_args, state), do: state

  defp analyze_piped_callback(lhs, rhs, state) do
    if tainted_expr?(lhs, state) do
      case piped_callback(rhs) do
        {:ok, callback} -> analyze_callback(callback, state)
        :error -> state
      end
    else
      state
    end
  end

  defp piped_callback(
         {{:., _dot_meta, [{:__aliases__, _alias_meta, [module]}, _fun]}, _meta, args}
       )
       when module in @enum_modules and is_list(args) do
    case Enum.find(args, &callback?/1) do
      nil -> :error
      callback -> {:ok, callback}
    end
  end

  defp piped_callback(_ast), do: :error

  defp callback?({:fn, _meta, clauses}) when is_list(clauses), do: true
  defp callback?({:&, _meta, [_body]}), do: true
  defp callback?(_ast), do: false

  defp analyze_callback(nil, state), do: state

  defp analyze_callback({:fn, _meta, clauses}, state) when is_list(clauses) do
    Enum.reduce(clauses, state, &analyze_tainted_callback_clause/2)
  end

  defp analyze_callback({:&, _meta, [body]}, state) do
    scoped = %{state | tainted_captures: MapSet.put(state.tainted_captures, 1)}
    {_tainted, scoped} = analyze(body, scoped)
    %{state | issues: scoped.issues}
  end

  defp analyze_callback(_callback, state), do: state

  defp analyze_clean_callback_clause({:->, _meta, [patterns, body]}, state) do
    scoped = bind_patterns(patterns, false, state)
    {_tainted, scoped} = analyze(body, scoped)
    %{state | issues: scoped.issues}
  end

  defp analyze_clean_callback_clause(_clause, state), do: state

  defp analyze_tainted_callback_clause({:->, _meta, [patterns, body]}, state) do
    scoped =
      patterns
      |> List.wrap()
      |> Enum.with_index(1)
      |> Enum.reduce(state, fn {pattern, index}, scoped ->
        bind_pattern(pattern, index == 1, false, scoped)
      end)

    {_tainted, scoped} = analyze(body, scoped)
    %{state | issues: scoped.issues}
  end

  defp analyze_tainted_callback_clause(_clause, state), do: state

  defp flag_sink(ast, state) do
    case sink_trigger(ast, state) do
      {:ok, trigger, meta} ->
        %{state | issues: [issue_for(state.issue_meta, trigger, meta) | state.issues]}

      :error ->
        state
    end
  end

  defp sink_trigger({:=~, meta, [left, right]}, state) do
    if tainted_expr?(left, state) or tainted_expr?(right, state) do
      {:ok, "=~", meta}
    else
      :error
    end
  end

  defp sink_trigger(
         {{:., _dot_meta, [{:__aliases__, _alias_meta, [:String]}, :contains?]}, meta, args},
         state
       )
       when is_list(args) do
    remote_sink_trigger(args, state, "String.contains?", meta)
  end

  defp sink_trigger(
         {{:., _dot_meta, [{:__aliases__, _alias_meta, [:Regex]}, fun]}, meta, args},
         state
       )
       when is_atom(fun) and is_list(args) do
    remote_sink_trigger(args, state, "Regex.#{fun}", meta)
  end

  defp sink_trigger(
         {{:., _dot_meta, [{:__aliases__, _alias_meta, [:Code]}, :eval_string]}, meta, args},
         state
       )
       when is_list(args) do
    remote_sink_trigger(args, state, "Code.eval_string", meta)
  end

  defp sink_trigger({:|>, _pipe_meta, [lhs, rhs]}, state) do
    if tainted_expr?(lhs, state) do
      piped_sink_trigger(rhs)
    else
      :error
    end
  end

  defp sink_trigger(_ast, _state), do: :error

  defp remote_sink_trigger(args, state, trigger, meta) do
    if Enum.any?(args, &tainted_expr?(&1, state)) do
      {:ok, trigger, meta}
    else
      :error
    end
  end

  defp piped_sink_trigger(
         {{:., _dot_meta, [{:__aliases__, _alias_meta, [:String]}, :contains?]}, meta, args}
       )
       when is_list(args) do
    {:ok, "String.contains?", meta}
  end

  defp piped_sink_trigger(
         {{:., _dot_meta, [{:__aliases__, _alias_meta, [:Regex]}, fun]}, meta, args}
       )
       when is_atom(fun) and is_list(args) do
    {:ok, "Regex.#{fun}", meta}
  end

  defp piped_sink_trigger(
         {{:., _dot_meta, [{:__aliases__, _alias_meta, [:Code]}, :eval_string]}, meta, args}
       )
       when is_list(args) do
    {:ok, "Code.eval_string", meta}
  end

  defp piped_sink_trigger(_ast), do: :error

  defp tainted_expr?(ast, state) do
    cond do
      source_read_call?(ast, state) ->
        true

      sink_expr?(ast) ->
        false

      true ->
        tainted_reference?(ast, state) or tainted_container?(ast, state)
    end
  end

  defp tainted_reference?(ast, state) do
    cond do
      variable?(ast) ->
        MapSet.member?(state.tainted_vars, variable_name(ast))

      module_attr_read?(ast) ->
        MapSet.member?(state.tainted_attrs, module_attr_name(ast))

      capture_arg?(ast) ->
        MapSet.member?(state.tainted_captures, capture_arg_position(ast))

      true ->
        false
    end
  end

  defp tainted_container?({:|>, _meta, [_lhs, _rhs]} = ast, state),
    do: piped_tainted_expr?(ast, state)

  defp tainted_container?(ast, state) when is_tuple(ast),
    do: ast |> Tuple.to_list() |> Enum.any?(&tainted_expr?(&1, state))

  defp tainted_container?(ast, state) when is_list(ast),
    do: Enum.any?(ast, &tainted_expr?(&1, state))

  defp tainted_container?(_ast, _state), do: false

  defp piped_tainted_expr?({:|>, _meta, [lhs, rhs]}, state) do
    if piped_sink?(rhs) do
      false
    else
      tainted_expr?(lhs, state) or tainted_expr?(rhs, state)
    end
  end

  defp source_read_call?(
         {{:., _dot_meta, [{:__aliases__, _alias_meta, [:File]}, reader]}, _meta, args},
         state
       )
       when reader in @source_readers and is_list(args) do
    args
    |> List.first()
    |> source_path_expr?(state)
  end

  defp source_read_call?({:|>, _pipe_meta, [path_expr, rhs]}, state) do
    source_path_expr?(path_expr, state) and piped_source_reader?(rhs)
  end

  defp source_read_call?(_ast, _state), do: false

  defp piped_source_reader?(
         {{:., _dot_meta, [{:__aliases__, _alias_meta, [:File]}, reader]}, _meta, args}
       )
       when reader in @source_readers and is_list(args) do
    true
  end

  defp piped_source_reader?(_ast), do: false

  defp source_path_expr?(nil, _state), do: false
  defp source_path_expr?(path, _state) when is_binary(path), do: source_path_literal?(path, true)

  defp source_path_expr?(
         {{:., _dot_meta, [{:__aliases__, _alias_meta, [:Path]}, :join]}, _meta, args},
         state
       )
       when is_list(args) do
    literal_join_source_path?(args) or Enum.any?(args, &source_path_piece?(&1, state))
  end

  defp source_path_expr?(ast, state) do
    cond do
      variable?(ast) ->
        MapSet.member?(state.source_path_vars, variable_name(ast))

      module_attr_read?(ast) ->
        MapSet.member?(state.source_path_attrs, module_attr_name(ast))

      true ->
        false
    end
  end

  defp source_path_piece?(path, _state) when is_binary(path),
    do: source_path_literal?(path, false)

  defp source_path_piece?(path, state) when is_list(path),
    do: literal_join_source_path?(path) or source_path_expr?(path, state)

  defp source_path_piece?(path, state), do: source_path_expr?(path, state)

  defp literal_join_source_path?(args) do
    case literal_join_path(args) do
      nil -> false
      path -> source_path_literal?(path, true)
    end
  end

  defp literal_join_path([parts]) when is_list(parts) do
    if Enum.all?(parts, &is_binary/1), do: Path.join(parts)
  end

  defp literal_join_path(args) when is_list(args) do
    if Enum.all?(args, &is_binary/1), do: Path.join(args)
  end

  defp source_path_literal?(path, allow_bare?) do
    normalized = normalize_path(path)

    source_extension?(normalized) and not under_test_path?(normalized) and
      not terminal_artifact_path?(normalized) and
      (allow_bare? or String.contains?(normalized, "/"))
  end

  defp normalize_path(path) do
    path
    |> String.replace("\\", "/")
    |> String.trim_leading("./")
  end

  defp source_extension?(path), do: Path.extname(path) in @source_extensions
  defp under_test_path?(path), do: path =~ ~r{(^|/)test/}

  defp terminal_artifact_path?(path) do
    Path.extname(path) in @terminal_artifact_extensions or path =~ ~r{(^|/)docs?/}
  end

  defp sink_expr?({:=~, _meta, [_left, _right]}), do: true

  defp sink_expr?(
         {{:., _dot_meta, [{:__aliases__, _alias_meta, [:String]}, :contains?]}, _meta, args}
       ),
       do: is_list(args)

  defp sink_expr?({{:., _dot_meta, [{:__aliases__, _alias_meta, [:Regex]}, fun]}, _meta, args}),
    do: is_atom(fun) and is_list(args)

  defp sink_expr?(
         {{:., _dot_meta, [{:__aliases__, _alias_meta, [:Code]}, :eval_string]}, _meta, args}
       ),
       do: is_list(args)

  defp sink_expr?(_ast), do: false

  defp piped_sink?(rhs) do
    match?({:ok, _trigger, _meta}, piped_sink_trigger(rhs))
  end

  defp bind_patterns(patterns, tainted?, state) do
    patterns
    |> List.wrap()
    |> Enum.reduce(state, &bind_pattern(&1, tainted?, false, &2))
  end

  defp bind_pattern(pattern, tainted?, source_path?, state) do
    pattern
    |> variables_in()
    |> Enum.reduce(state, fn variable, state ->
      %{
        state
        | source_path_vars: put_or_delete(state.source_path_vars, variable, source_path?),
          tainted_vars: put_or_delete(state.tainted_vars, variable, tainted?)
      }
    end)
  end

  defp bind_attr(name, tainted?, source_path?, state) do
    %{
      state
      | source_path_attrs: put_or_delete(state.source_path_attrs, name, source_path?),
        tainted_attrs: put_or_delete(state.tainted_attrs, name, tainted?)
    }
  end

  defp put_or_delete(set, value, true), do: MapSet.put(set, value)
  defp put_or_delete(set, value, false), do: MapSet.delete(set, value)

  defp variables_in({:^, _meta, [_pinned]}), do: []
  defp variables_in({:@, _meta, [_attr]}), do: []

  defp variables_in(ast) do
    cond do
      variable?(ast) ->
        name = variable_name(ast)
        if name == :_, do: [], else: [name]

      is_tuple(ast) ->
        ast |> Tuple.to_list() |> Enum.flat_map(&variables_in/1)

      is_list(ast) ->
        Enum.flat_map(ast, &variables_in/1)

      true ->
        []
    end
  end

  defp variable?({name, _meta, context}) when is_atom(name) and is_atom(context), do: true
  defp variable?(_ast), do: false

  defp variable_name({name, _meta, _context}), do: name

  defp module_attr_read?({:@, _meta, [{name, _attr_meta, nil}]}) when is_atom(name), do: true
  defp module_attr_read?(_ast), do: false

  defp module_attr_name({:@, _meta, [{name, _attr_meta, nil}]}), do: name

  defp capture_arg?({:&, _meta, [position]}) when is_integer(position), do: true
  defp capture_arg?(_ast), do: false

  defp capture_arg_position({:&, _meta, [position]}), do: position

  defp issue_for(issue_meta, trigger, meta) do
    format_issue(issue_meta,
      message:
        "`#{trigger}` inspects text read from a non-test Elixir source file. " <>
          "Replace source-grep assertions with behavioural contract coverage in " <>
          "`#{@contract_path}`. Doc/artifact reads (`.md`, `.txt`, `.yml`, `.yaml`) " <>
          "are intentionally outside this check; use `:excluded_paths` only as a " <>
          "shrinking migration bridge.",
      trigger: trigger,
      line_no: Keyword.get(meta, :line)
    )
  end
end
