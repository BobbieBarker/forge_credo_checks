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
      forwards a load-bearing signal to a process — `send/2` to a pid, a
      `GenServer.call`/`cast`, or any application GenServer client API — the
      telemetry bus silently becomes part of the control path. The failure mode
      is quiet: a raising handler is auto-detached by the telemetry runtime, so
      the behavior it drove simply stops with no error and no restart. The
      idiomatic mechanism for delivering signals between processes is
      `Phoenix.PubSub`.

      This check flags a `:telemetry.attach/4` or `:telemetry.attach_many/4`
      whose handler argument is an inline anonymous function (`fn`) whose body
      performs a control-flow side effect: `send/2`, `:erlang.send/2`,
      `GenServer.call/2,3`, or `GenServer.cast/2`. Observation-only handlers
      (metric emission, span recording, logging) are not flagged.

      ## Known limits

      Detection is syntactic and scoped to **inline anonymous-function
      handlers** — a `fn` literal passed directly as the handler argument.

      * **Named MFA handlers are out of scope.** `:telemetry.attach/4` with an
        `{Module, :function, config}` tuple names a handler in a different
        module; the attach call site holds no body to inspect. Resolving the
        referenced function's body requires cross-file/whole-program analysis,
        which this repo's checks deliberately do not perform (see the
        `PortProducerBoundary` "Known limits" precedent). Such handlers are
        not flagged by this pass.
      * A handler passed as a **bound variable** (`:telemetry.attach(name,
        event, handler_fn, config)`) likewise carries no body at the call site
        and is not flagged.
      * Aliased or imported control-flow calls (e.g. `alias GenServer, as: GS;
        GS.cast(...)`) are not resolved; detection matches the canonical
        `GenServer.*`, `send`, and `:erlang.send` forms.

      ## Bad

          :telemetry.attach("governor", [:app, :dispatch], fn _, _, _, _ ->
            GenServer.cast(pid, :adjust_limit)
          end, nil)

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
           excluded_paths: [~r"^lib/legacy/telemetry_bridge\.ex$"]}

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
      Credo.Code.prewalk(source_file, &traverse(&1, &2, issue_meta))
    end
  end

  defp excluded_path?(%{filename: filename}, params) when is_binary(filename) do
    params
    |> Params.get(:excluded_paths, __MODULE__)
    |> Enum.any?(&(filename =~ &1))
  end

  defp excluded_path?(_source_file, _params), do: false

  # :telemetry.attach/4 or :telemetry.attach_many/4 with an inline fn handler.
  # The handler is the 4th argument (index 3); it may be a bare `fn` or a
  # `fn` wrapped by a `__block__`. We descend into the fn body and report any
  # control-flow call found, attributing the issue to the attach call's line.
  defp traverse(
         {{:., dot_meta, [:telemetry, fun]}, call_meta, args} = ast,
         issues,
         issue_meta
       )
       when fun in @telemetry_attaches and is_list(args) do
    case find_inline_handler(args) do
      {:ok, fn_ast} ->
        attach_line = Keyword.get(call_meta, :line, Keyword.get(dot_meta, :line))
        new_issues = control_flow_issues(fn_ast, issue_meta, attach_line)
        {ast, new_issues ++ issues}

      :none ->
        {ast, issues}
    end
  end

  defp traverse(ast, issues, _issue_meta), do: {ast, issues}

  # The handler argument position is index 3 for both attach/4 and attach_many/4.
  # A direct `fn` literal lands here as `{:fn, _, clauses}`. MFA tuples, bound
  # variables, and any other form are out of scope (see "Known limits").
  defp find_inline_handler([_, _, {:fn, _, _} = fn_ast | _]), do: {:ok, fn_ast}

  defp find_inline_handler(_args), do: :none

  defp control_flow_issues(fn_ast, issue_meta, attach_line) do
    {_ast, issues} =
      Macro.prewalk(fn_ast, [], fn
        # local send/2 (Kernel import)
        {:send, meta, [_pid, _msg]} = ast, issues ->
          {ast, [issue_for(issue_meta, "send", attach_line, meta) | issues]}

        # :erlang.send/2
        {{:., _, [:erlang, :send]}, meta, [_pid, _msg]} = ast, issues ->
          {ast, [issue_for(issue_meta, ":erlang.send", attach_line, meta) | issues]}

        # GenServer.call / GenServer.cast
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
