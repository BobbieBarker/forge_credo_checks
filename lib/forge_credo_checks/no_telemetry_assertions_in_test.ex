defmodule ForgeCredoChecks.NoTelemetryAssertionsInTest do
  @moduledoc """
  Rejects project tests that treat telemetry instrumentation as a behavioral contract.

  The check is deliberately limited to test files. Production telemetry
  attachment and emission remain valid observability code.
  """

  use Credo.Check,
    base_priority: :high,
    category: :warning,
    param_defaults: [
      telemetry_event_roots: [
        :dispatch_admission,
        :dispatch_budget,
        :forge_reactor,
        :forge_symphony,
        :pipeline,
        :pr_fix
      ]
    ],
    explanations: [
      check: """
      Tests must assert the state change, persisted record, cache write, or
      Phoenix.PubSub domain event produced by behavior, not its telemetry.

      ## Configuration

      `telemetry_event_roots` lists the first atom in project telemetry event
      names represented as lists. Configure every event root emitted by the
      project so assertions against those events are rejected. Tuple events
      tagged `:telemetry` or `:telemetry_event` are always rejected regardless
      of this parameter.
      """,
      params: [
        telemetry_event_roots: "First atoms identifying project telemetry event-name lists."
      ]
    ]

  @assertion_macros [:assert_receive, :assert_received, :refute_receive]
  @attach_functions [:attach, :attach_many]

  alias Credo.{Code, IssueMeta}

  @doc false
  @spec run(Credo.SourceFile.t(), keyword()) :: [Credo.Issue.t()]
  def run(%{filename: filename} = source_file, params \\ []) do
    if test_file?(filename) do
      issue_meta = IssueMeta.for(source_file, params)
      telemetry_event_roots = Params.get(params, :telemetry_event_roots, __MODULE__)

      Code.prewalk(
        source_file,
        &traverse(&1, &2, issue_meta, telemetry_event_roots)
      )
    else
      []
    end
  end

  defp test_file?(filename) when is_binary(filename) do
    filename
    |> Path.split()
    |> Enum.any?(&(&1 === "test"))
  end

  defp test_file?(_filename), do: false

  defp traverse(
         {{:., dot_meta, [module, function]}, call_meta, _args} = ast,
         issues,
         issue_meta,
         _telemetry_event_roots
       )
       when (module === :telemetry and function in @attach_functions) or
              (module === :telemetry_test and function === :attach_event_handlers) do
    line = Keyword.get(call_meta, :line, Keyword.get(dot_meta, :line))
    {ast, [issue_for(issue_meta, "#{inspect(module)}.#{function}", line) | issues]}
  end

  defp traverse(
         {assertion, meta, args} = ast,
         issues,
         issue_meta,
         telemetry_event_roots
       )
       when assertion in @assertion_macros and is_list(args) do
    if Enum.any?(args, &contains_telemetry_event?(&1, telemetry_event_roots)) do
      {ast, [issue_for(issue_meta, Atom.to_string(assertion), Keyword.get(meta, :line)) | issues]}
    else
      {ast, issues}
    end
  end

  defp traverse(ast, issues, _issue_meta, _telemetry_event_roots), do: {ast, issues}

  defp contains_telemetry_event?(ast, telemetry_event_roots) do
    {_ast, found?} =
      Macro.prewalk(ast, false, fn
        {:{}, _meta, [tag | _rest]} = node, _found?
        when tag in [:telemetry, :telemetry_event] ->
          {node, true}

        {:{}, _meta, [[root | _event] | _rest]} = node, found? ->
          {node, found? or root in telemetry_event_roots}

        node, found? ->
          {node, found?}
      end)

    found?
  end

  defp issue_for(issue_meta, trigger, line_no) do
    message = """
    Telemetry is observability, not a test contract. Assert the resulting state \
    change or Phoenix.PubSub domain event instead.
    """

    format_issue(issue_meta,
      message: message,
      trigger: trigger,
      line_no: line_no
    )
  end
end
