defmodule ForgeCredoChecks.NoTelemetryAssertionsInTest do
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
      Assert the behaviour, not the instrumentation that observes it.

      ## Why

      A telemetry event is an observability signal, not a contract. Asserting
      on one couples the test to the event name, the measurement map, and the
      metadata shape — all of which are meant to be free to change — while
      proving nothing about whether the work actually happened. An emit with a
      broken write behind it passes such a test.

      Telemetry is also the wrong delivery mechanism for a test signal: a
      handler that raises is detached by `:telemetry` permanently and silently,
      so the test that depended on it starts passing vacuously. When behaviour
      genuinely needs to notify another process, the mechanism is
      `Phoenix.PubSub`, and that domain event is what the test should assert.

      ## The fix is not deletion

      Deleting the test, deleting the `:telemetry.attach` call, or deleting the
      assertion silences this check and removes the coverage. The attachment
      and the assertions below it are one unit: replace the whole telemetry
      round-trip with an assertion on the observable outcome the behaviour
      produces.

      ## Bad

          :telemetry.attach(
            "test-order-placed",
            [:my_app, :order, :placed],
            fn event, measurements, metadata, _config ->
              send(self(), {:telemetry, event, measurements, metadata})
            end,
            nil
          )

          assert {:ok, _order} = Orders.place(params)
          assert_receive {:telemetry, [:my_app, :order, :placed], %{}, %{id: id}}

      ## Good

          # Assert the persisted record and the domain event the behaviour
          # actually produces. No attachment, no handler, nothing to detach.
          Orders.subscribe(order_id)

          assert {:ok, %Order{id: id}} = Orders.place(params)
          assert %Order{status: :placed, total: 1_200} = Repo.get!(Order, id)
          assert_receive {:order_placed, ^order_id}

      If the behaviour has no observable outcome other than its telemetry, that
      is the finding: give it one. Return the value, persist the record, or
      broadcast a `Phoenix.PubSub` domain event, then assert on that.

      ## What is flagged

      In test files only:

        * `:telemetry.attach/4`, `:telemetry.attach_many/4`, and
          `:telemetry_test.attach_event_handlers/2`, whether called directly or
          through `apply/3`;
        * `assert_receive`, `assert_received`, and `refute_receive` whose
          message contains a tuple tagged `:telemetry` or `:telemetry_event`,
          or one whose leading element is an event-name list beginning with a
          root in `telemetry_event_roots`. Tuples of every size are matched,
          including two-element `{:telemetry, payload}` messages.

      An event name lifted into a module attribute in the same file
      (`@event [:my_app, :thing, :done]`, then `assert_receive {@event, ...}`)
      is resolved back to the list, so the indirection does not hide it.

      Production telemetry attachment and emission are untouched — the check
      never runs outside test files.

      ## Configuration

      `telemetry_event_roots` lists the first atom of each project telemetry
      event name. Declare every root the project emits so assertions against
      those events are rejected; tuples tagged `:telemetry` or
      `:telemetry_event` are rejected regardless of this parameter.

          {ForgeCredoChecks.NoTelemetryAssertionsInTest,
           telemetry_event_roots: [:my_app, :my_library]}
      """,
      params: [
        telemetry_event_roots: "First atoms identifying project telemetry event-name lists."
      ]
    ]

  @assertion_macros [:assert_receive, :assert_received, :refute_receive]
  @attach_functions [:attach, :attach_many]
  @telemetry_tags [:telemetry, :telemetry_event]

  alias Credo.{Code, IssueMeta}

  @doc false
  @spec run(Credo.SourceFile.t(), keyword()) :: [Credo.Issue.t()]
  def run(%{filename: filename} = source_file, params \\ []) do
    if test_file?(filename) do
      issue_meta = IssueMeta.for(source_file, params)
      Code.prewalk(source_file, &traverse(&1, &2, issue_meta, event_context(source_file, params)))
    else
      []
    end
  end

  # Everything needed to recognise a telemetry event name: the configured roots,
  # plus any event name this file lifted into a module attribute.
  defp event_context(source_file, params) do
    %{
      roots: Params.get(params, :telemetry_event_roots, __MODULE__),
      attribute_events: attribute_events(source_file)
    }
  end

  # `@event [:my_app, :thing, :done]` -- an event name hoisted out of the
  # assertion. Resolved here so the indirection cannot hide the event.
  defp attribute_events(source_file) do
    Code.prewalk(source_file, &collect_attribute_event/2, %{})
  end

  defp collect_attribute_event(
         {:@, _meta, [{name, _attr_meta, [[root | _tail] = event]}]} = ast,
         attributes
       )
       when is_atom(name) and is_atom(root) do
    {ast, Map.put(attributes, name, event)}
  end

  defp collect_attribute_event(ast, attributes), do: {ast, attributes}

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
         _context
       )
       when (module === :telemetry and function in @attach_functions) or
              (module === :telemetry_test and function === :attach_event_handlers) do
    line = Keyword.get(call_meta, :line, Keyword.get(dot_meta, :line))
    {ast, [issue_for(issue_meta, "#{inspect(module)}.#{function}", line) | issues]}
  end

  # `apply(:telemetry, :attach, [...])` -- the same attachment behind a runtime
  # dispatch, which the remote-call clause above cannot see.
  defp traverse({:apply, meta, [module, function, args]} = ast, issues, issue_meta, _context)
       when is_list(args) and
              ((module === :telemetry and function in @attach_functions) or
                 (module === :telemetry_test and function === :attach_event_handlers)) do
    {ast,
     [
       issue_for(issue_meta, "#{inspect(module)}.#{function}", Keyword.get(meta, :line))
       | issues
     ]}
  end

  defp traverse({assertion, meta, args} = ast, issues, issue_meta, context)
       when assertion in @assertion_macros and is_list(args) do
    if Enum.any?(args, &contains_telemetry_event?(&1, context)) do
      {ast, [issue_for(issue_meta, Atom.to_string(assertion), Keyword.get(meta, :line)) | issues]}
    else
      {ast, issues}
    end
  end

  defp traverse(ast, issues, _issue_meta, _context), do: {ast, issues}

  defp contains_telemetry_event?(ast, context) do
    {_ast, found?} =
      Macro.prewalk(ast, false, fn
        node, true -> {node, true}
        node, false -> {node, telemetry_message?(node, context)}
      end)

    found?
  end

  # Tuples of three or more elements are `{:{}, meta, args}` in the AST...
  defp telemetry_message?({:{}, _meta, [tag | _rest]}, _context) when tag in @telemetry_tags,
    do: true

  defp telemetry_message?({:{}, _meta, [event | _rest]}, context),
    do: telemetry_event?(event, context)

  # ...while a two-element tuple stays a literal `{a, b}` and needs its own
  # clauses, which is why `{:telemetry, payload}` used to slip through.
  defp telemetry_message?({tag, _payload}, _context) when tag in @telemetry_tags, do: true
  defp telemetry_message?({event, _payload}, context), do: telemetry_event?(event, context)

  defp telemetry_message?(_node, _context), do: false

  defp telemetry_event?([root | _tail], context) when is_atom(root), do: root in context.roots

  defp telemetry_event?({:@, _meta, [{name, _attr_meta, attr_context}]}, context)
       when is_atom(name) and is_atom(attr_context) do
    context.attribute_events
    |> Map.get(name, [])
    |> telemetry_event?(context)
  end

  defp telemetry_event?(_event, _context), do: false

  defp issue_for(issue_meta, trigger, line_no) do
    format_issue(issue_meta,
      message: message_for(trigger),
      trigger: trigger,
      line_no: line_no
    )
  end

  defp message_for("assert" <> _rest = trigger), do: assertion_message(trigger)
  defp message_for("refute" <> _rest = trigger), do: assertion_message(trigger)
  defp message_for(trigger), do: attach_message(trigger)

  defp assertion_message(trigger) do
    "`#{trigger}` on a telemetry event asserts that instrumentation fired, not that the " <>
      "behaviour happened. Assert the state change, persisted record, cache write, or " <>
      "Phoenix.PubSub domain event it produces instead. Deleting the assertion is not the fix; " <>
      "if the behaviour has no observable outcome besides telemetry, give it one."
  end

  defp attach_message(trigger) do
    "`#{trigger}` wires this test to observability instrumentation rather than behaviour, and a " <>
      "handler that raises is detached permanently and silently, so the test then passes " <>
      "vacuously. Deleting this attachment and orphaning the assertions below it is not the " <>
      "fix: replace the whole telemetry round-trip with an assertion on the state change, " <>
      "persisted record, or Phoenix.PubSub domain event the behaviour produces."
  end
end
