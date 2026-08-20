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

      In test files, a `refute_receive` or `refute_received` whose message is a
      tuple of any size tagged with an event listed in `global_subscriptions`,
      where *every* payload element is a plain variable, and where the file
      takes the corresponding subscription at arity zero — as a qualified call
      (`Events.subscribe_mcp()`) or as an imported local one (`subscribe_mcp()`).

      A leading underscore is irrelevant: `meta` is exactly as unpinned as
      `_meta`, so renaming one to the other does not silence the check. One
      pinned or destructured element is enough to scope the assertion and clear
      it.

      Not flagged: a scoped subscription (`subscribe_dispatch(scope)`, any
      non-zero arity), since scoped delivery does not carry other tests'
      messages; and any tag not listed for a subscription the file takes.

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

  @negative_assertions [:refute_receive, :refute_received]

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

  defp test_file?(_filename), do: false

  defp globally_subscribed_tags(source_file, subscriptions) do
    Code.prewalk(
      source_file,
      &collect_subscription(&1, &2, subscriptions),
      MapSet.new()
    )
  end

  # `Events.subscribe_mcp()` -- the subscription taken as a qualified call.
  defp collect_subscription(
         {{:., _dot_meta, [_module, function]}, _call_meta, []} = ast,
         tags,
         subscriptions
       )
       when is_atom(function) do
    {ast, put_subscribed_tags(tags, subscriptions, function)}
  end

  # `subscribe_mcp()` -- the same subscription imported into the test case.
  defp collect_subscription({function, _meta, []} = ast, tags, subscriptions)
       when is_atom(function) do
    {ast, put_subscribed_tags(tags, subscriptions, function)}
  end

  defp collect_subscription(ast, tags, _subscriptions), do: {ast, tags}

  defp put_subscribed_tags(tags, subscriptions, function) do
    subscriptions
    |> Keyword.get(function, [])
    |> Enum.reduce(tags, &MapSet.put(&2, &1))
  end

  defp traverse({assertion, meta, [message | _rest]} = ast, issues, issue_meta, subscribed_tags)
       when assertion in @negative_assertions do
    if wildcard_global_refute?(message, subscribed_tags) do
      {ast, [issue_for(issue_meta, assertion, meta) | issues]}
    else
      {ast, issues}
    end
  end

  defp traverse(ast, issues, _issue_meta, _subscribed_tags), do: {ast, issues}

  # `{tag, payload}` -- a two-element message is a literal tuple in the AST.
  defp wildcard_global_refute?({tag, payload}, subscribed_tags) when is_atom(tag) do
    subscribed?(tag, subscribed_tags) and wildcard_payload?([payload])
  end

  # `{tag, a, b}` -- three or more elements are `{:{}, meta, args}`.
  defp wildcard_global_refute?({:{}, _meta, [tag | payload]}, subscribed_tags)
       when is_atom(tag) do
    subscribed?(tag, subscribed_tags) and wildcard_payload?(payload)
  end

  defp wildcard_global_refute?(_message, _subscribed_tags), do: false

  defp subscribed?(tag, subscribed_tags), do: MapSet.member?(subscribed_tags, tag)

  # Nothing in the payload ties the message to this test: every element is a
  # plain variable, bound to whatever arrives. A single pinned or destructured
  # field is enough to scope the assertion, so only an all-variable payload is
  # a wildcard. Leading underscores are irrelevant -- `meta` is as unpinned as
  # `_meta`, and renaming one to the other must not silence the check.
  defp wildcard_payload?([]), do: false
  defp wildcard_payload?(payload), do: Enum.all?(payload, &unbound_variable?/1)

  defp unbound_variable?({name, _meta, context}) when is_atom(name) and is_atom(context), do: true
  defp unbound_variable?(_element), do: false

  defp issue_for(issue_meta, assertion, meta) do
    format_issue(issue_meta,
      message:
        "`#{assertion}` on a globally subscribed PubSub event matches any producer's message, " <>
          "including one from an unrelated async test, so it fails only under an unlucky " <>
          "interleaving and reruns green in isolation. Pin the field that identifies this " <>
          "test's event (`%{transport: ^transport}`), or take the subscription with a scope. " <>
          "Deleting or widening the assertion is not the fix.",
      trigger: Atom.to_string(assertion),
      line_no: Keyword.get(meta, :line)
    )
  end
end
