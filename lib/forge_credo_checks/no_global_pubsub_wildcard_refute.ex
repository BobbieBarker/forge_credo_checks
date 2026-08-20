defmodule ForgeCredoChecks.NoGlobalPubSubWildcardRefute do
  use Credo.Check,
    base_priority: :high,
    category: :warning,
    param_defaults: [
      global_subscriptions: [
        subscribe_dispatch: [:dispatch_complete, :dispatch_fallthrough],
        subscribe_mcp: [:mcp_delivery_dropped, :mcp_handler_registered]
      ]
    ],
    explanations: [
      check: """
      A negative assertion on a globally subscribed PubSub event must pin the
      payload field that identifies *this* test's event.

      ## Why

      A global `Phoenix.PubSub` subscription — one taken with no scope argument
      — delivers every message on the topic to the subscribing process,
      including messages produced by every other `async: true` test sharing the
      VM. A `refute_receive` whose payload is an unbound variable matches *any*
      of them, so the assertion says "no test anywhere emitted this event",
      which is not what the test means and not something the test controls.

      The result is a flaky failure that appears only when an unrelated test
      happens to interleave, and that reruns green in isolation. Pinning an
      identifying field narrows the assertion back to the event the test is
      actually about.

      ## Bad

          Events.subscribe_mcp()
          refute_receive {:mcp_delivery_dropped, _metadata}, 50

      ## Good

          # Pin the field that identifies this test's event.
          transport = start_transport()
          Events.subscribe_mcp()
          refute_receive {:mcp_delivery_dropped, %{transport: ^transport}}, 50

          # Or scope the subscription so unrelated producers never arrive.
          Events.subscribe_mcp(scope)
          refute_receive {:mcp_delivery_dropped, _metadata}, 50

      Widening the assertion — deleting it, or swapping `refute_receive` for a
      bare `refute` — is not a fix. The test still needs to prove the event did
      not fire for *its own* subject.

      ## What is flagged

      In test files, a `refute_receive` whose first argument is a tuple tagged
      with an event listed in `global_subscriptions`, where the payload is an
      unbound variable, and where the file takes the corresponding subscription
      at arity zero.

      ## Configuration

      `global_subscriptions` maps each project's zero-arity subscribe function
      to the event tags that subscription delivers. Only files that call one of
      these functions are checked, and only those tags are flagged, so a
      project that does not use them sees no issues. Declare your own:

          {ForgeCredoChecks.NoGlobalPubSubWildcardRefute,
           global_subscriptions: [
             subscribe_orders: [:order_placed, :order_cancelled]
           ]}
      """,
      params: [
        global_subscriptions:
          "Keyword list mapping a zero-arity subscribe function to the event tags it delivers."
      ]
    ]

  alias Credo.{Code, IssueMeta}

  @doc false
  @spec run(Credo.SourceFile.t(), keyword()) :: [Credo.Issue.t()]
  def run(%{filename: filename} = source_file, params \\ []) do
    if test_file?(filename) do
      issue_meta = IssueMeta.for(source_file, params)
      subscriptions = Params.get(params, :global_subscriptions, __MODULE__)
      subscribed_tags = globally_subscribed_tags(source_file, subscriptions)
      Code.prewalk(source_file, &traverse(&1, &2, issue_meta, subscribed_tags))
    else
      []
    end
  end

  defp test_file?(filename) when is_binary(filename) do
    filename
    |> Path.split()
    |> Enum.any?(&(&1 === "test"))
  end

  defp globally_subscribed_tags(source_file, subscriptions) do
    Code.prewalk(
      source_file,
      fn
        {{:., _dot_meta, [_module, function]}, _call_meta, []} = ast, tags ->
          {ast, put_subscribed_tags(tags, subscriptions, function)}

        ast, tags ->
          {ast, tags}
      end,
      MapSet.new()
    )
  end

  defp put_subscribed_tags(tags, subscriptions, function) do
    subscriptions
    |> Keyword.get(function, [])
    |> Enum.reduce(tags, &MapSet.put(&2, &1))
  end

  defp traverse(
         {:refute_receive, meta, [{tag, payload} | _rest]} = ast,
         issues,
         issue_meta,
         subscribed_tags
       )
       when is_atom(tag) do
    maybe_flag_wildcard(ast, meta, tag, payload, issues, issue_meta, subscribed_tags)
  end

  defp traverse(ast, issues, _issue_meta, _subscribed_tags), do: {ast, issues}

  defp maybe_flag_wildcard(ast, meta, tag, payload, issues, issue_meta, subscribed_tags) do
    if MapSet.member?(subscribed_tags, tag) and wildcard_variable?(payload) do
      issue =
        format_issue(issue_meta,
          message:
            "Pin identifying payload fields when refuting a globally subscribed PubSub event.",
          trigger: "refute_receive",
          line_no: Keyword.get(meta, :line)
        )

      {ast, [issue | issues]}
    else
      {ast, issues}
    end
  end

  defp wildcard_variable?({name, _meta, context})
       when is_atom(name) and is_atom(context) do
    name
    |> Atom.to_string()
    |> String.starts_with?("_")
  end

  defp wildcard_variable?(_payload), do: false
end
