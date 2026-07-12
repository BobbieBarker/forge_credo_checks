defmodule ForgeCredoChecks.TelemetryControlFlow do
  @moduledoc false

  use Credo.Check,
    base_priority: :high,
    category: :warning,
    param_defaults: [excluded_paths: []],
    explanations: [
      check: """
      Telemetry handlers must be observation-only; using them as a control-flow
      bus is a silent-degradation smell.

      ## Why

      `:telemetry` handlers are meant to observe events (emit metrics, record
      spans, log) without influencing the system they observe. When a handler
      forwards a load-bearing signal to a process -- `send/2` to a pid, a
      `GenServer.call`/`cast`, or any application GenServer client API -- the
      telemetry bus silently becomes part of the control path. The failure mode
      is quiet: a raising handler is auto-detached by the telemetry runtime, so
      the behavior it drove simply stops with no error and no restart. The
      idiomatic mechanism for delivering signals between processes is
      `Phoenix.PubSub`.

      This check flags a `:telemetry.attach/4` or `:telemetry.attach_many/4`
      whose handler argument contains control-flow side effects: `send/2`,
      `:erlang.send/2`, `GenServer.call/2,3`, or `GenServer.cast/2`.

      Detection covers two forms:

      1. **Inline anonymous functions** -- a `fn` literal passed directly as
         the handler argument.
      2. **Same-file function captures** -- `&func_name/arity` or
         `&__MODULE__.func_name/arity` where the captured function is defined
         in the same source file. The check resolves the function body and
         inspects it for control-flow calls.

      Observation-only handlers (metric emission, span recording, logging)
      are not flagged regardless of form.

      ## Known limits

      * **Named MFA-tuple handlers are out of scope.** `:telemetry.attach/4`
        with a `{Module, :function, config}` tuple requires cross-file
        analysis to resolve and is not flagged.
      * **Cross-module captures** (`&OtherModule.func/arity` where
        `OtherModule` is not defined in the same file) are not resolved.
      * A handler passed as a **bound variable** (`:telemetry.attach(name,
        event, handler_fn, config)`) likewise carries no body at the call site
        and is not flagged.
      * Aliased or imported control-flow calls (e.g. `alias GenServer, as: GS;
        GS.cast(...)`) are not resolved; detection matches the canonical
        `GenServer.*`, `send`, and `:erlang.send` forms.
      * For same-file captures, if the function delegates to another function
        that performs control flow, only direct control-flow calls in the
        captured function's body are detected (no transitive resolution).

      ## Bad

          :telemetry.attach("governor", [:app, :dispatch], fn _, _, _, _ ->
            GenServer.cast(pid, :adjust_limit)
          end, nil)

          # Same-file capture with control flow in the referenced function
          :telemetry.attach("broker", [:budget, :release],
            &__MODULE__.handle_release/4, nil)

          defp handle_release(_event, _measures, %{pid: pid}, _config) do
            send(pid, :budget_released)
          end

      ## Good

          # observation only
          :telemetry.attach("metric", [:app, :dispatch], fn _event, measures, _meta, _conf ->
            :telemetry.execute([:app, :metric], measures, %{})
          end, nil)

          # cross-process signaling over PubSub, not the telemetry bus
          Phoenix.PubSub.broadcast(MyApp.PubSub, "dispatch", {:dispatched, id})

      ## Configuration

      `excluded_paths` is a list of patterns (regexes or substrings) matched
      against each file's path; a matching file is skipped. Use it only as a
      shrinking migration bridge while moving an existing telemetry-as-bus site
      onto `Phoenix.PubSub`:

          {ForgeCredoChecks.TelemetryControlFlow,
           excluded_paths: [~r"^lib/legacy/telemetry_bridge\\.ex$"]}

      Credo's `# credo:disable-for-next-line` escape hatch is honored
      automatically; use it to suppress a single intentional exception:

          # credo:disable-for-next-line ForgeCredoChecks.TelemetryControlFlow
          :telemetry.attach("intentional", [:app, :event], fn _, _, _, _ -> ... end, nil)
      """,
      params: [
        excluded_paths: "Paths skipped entirely (regexes or substrings)."
      ]
    ]

  @telemetry_attaches [:attach, :attach_many]

  @genserver_calls [:call, :cast]

  @doc false
  def run(source_file, params \\ []) do
    if excluded_path?(source_file, params) do
      []
    else
      issue_meta = IssueMeta.for(source_file, params)
      fn_defs = collect_function_defs(source_file)
      Credo.Code.prewalk(source_file, &traverse(&1, &2, issue_meta, fn_defs))
    end
  end

  defp excluded_path?(%{filename: filename}, params) when is_binary(filename) do
    params
    |> Params.get(:excluded_paths, __MODULE__)
    |> Enum.any?(&(filename =~ &1))
  end

  defp excluded_path?(_source_file, _params), do: false

  # --- First pass: collect function definitions by {name, arity} ---

  defp collect_function_defs(source_file) do
    source_file
    |> Credo.Code.prewalk(&collect_def/2)
    |> Enum.group_by(
      fn {name, arity, _body} -> {name, arity} end,
      fn {_name, _arity, body} -> body end
    )
  end

  defp collect_def({def_type, _meta, [{:when, _, [{name, _, args} | _]}, body]} = ast, acc)
       when def_type in [:def, :defp] and is_atom(name) and is_list(args) do
    {ast, [{name, length(args), body} | acc]}
  end

  defp collect_def({def_type, _meta, [{name, _, args}, body]} = ast, acc)
       when def_type in [:def, :defp] and is_atom(name) and is_list(args) do
    {ast, [{name, length(args), body} | acc]}
  end

  defp collect_def(ast, acc), do: {ast, acc}

  # --- Second pass: detect telemetry attaches with control-flow handlers ---

  defp traverse(
         {{:., dot_meta, [:telemetry, fun]}, call_meta, args} = ast,
         issues,
         issue_meta,
         fn_defs
       )
       when fun in @telemetry_attaches and is_list(args) do
    attach_line = Keyword.get(call_meta, :line, Keyword.get(dot_meta, :line))

    new_issues =
      case find_handler(args) do
        {:inline, fn_ast} ->
          control_flow_issues(fn_ast, issue_meta, attach_line)

        {:capture, name, arity} ->
          resolve_capture_issues(fn_defs, name, arity, issue_meta, attach_line)

        :none ->
          []
      end

    {ast, new_issues ++ issues}
  end

  defp traverse(ast, issues, _issue_meta, _fn_defs), do: {ast, issues}

  # --- Handler detection ---

  defp find_handler([_, _, handler | _]), do: classify_handler(handler)
  defp find_handler(_args), do: :none

  defp classify_handler({:fn, _, _} = fn_ast), do: {:inline, fn_ast}

  # &func_name/arity (local capture)
  defp classify_handler({:&, _, [{:/, _, [{name, _, ctx}, arity]}]})
       when is_atom(name) and is_integer(arity) and (is_atom(ctx) or is_nil(ctx)) do
    {:capture, name, arity}
  end

  # &__MODULE__.func_name/arity
  defp classify_handler(
         {:&, _, [{:/, _, [{{:., _, [{:__MODULE__, _, _}, name]}, _, []}, arity]}]}
       )
       when is_atom(name) and is_integer(arity) do
    {:capture, name, arity}
  end

  defp classify_handler(_), do: :none

  # --- Capture resolution ---

  defp resolve_capture_issues(fn_defs, name, arity, issue_meta, attach_line) do
    case Map.get(fn_defs, {name, arity}) do
      nil ->
        []

      bodies ->
        bodies
        |> Enum.flat_map(&control_flow_issues(&1, issue_meta, attach_line))
        |> Enum.uniq_by(fn issue -> {issue.trigger, issue.line_no} end)
    end
  end

  # --- Control-flow detection in a handler body ---

  defp control_flow_issues(body_ast, issue_meta, attach_line) do
    {_ast, issues} =
      Macro.prewalk(body_ast, [], fn
        {:send, meta, [_pid, _msg]} = ast, issues ->
          {ast, [issue_for(issue_meta, "send", attach_line, meta) | issues]}

        {{:., _, [:erlang, :send]}, meta, [_pid, _msg]} = ast, issues ->
          {ast, [issue_for(issue_meta, ":erlang.send", attach_line, meta) | issues]}

        {{:., _, [{:__aliases__, _, [:GenServer]}, fun]}, meta, _args} = ast, issues
        when fun in @genserver_calls ->
          {ast, [issue_for(issue_meta, "GenServer.#{fun}", attach_line, meta) | issues]}

        ast, issues ->
          {ast, issues}
      end)

    Enum.reverse(issues)
  end

  defp issue_for(issue_meta, trigger, attach_line, call_meta) do
    call_line = Keyword.get(call_meta, :line, attach_line)

    format_issue(issue_meta,
      message:
        "`#{trigger}` inside a telemetry handler uses the observation bus as " <>
          "control flow: a raising handler is auto-detached, so the behavior " <>
          "quietly stops. Deliver load-bearing signals via `Phoenix.PubSub` " <>
          "and keep telemetry handlers observation-only.",
      trigger: trigger,
      line_no: call_line
    )
  end
end
