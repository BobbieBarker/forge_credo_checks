defmodule ForgeCredoChecks.NoGlobalPubSubWildcardRefute do
  @moduledoc """
  Rejects wildcard negative assertions against globally subscribed PubSub events.

  A global Phoenix.PubSub subscription receives events from every async test in
  the VM. Negative assertions must therefore pin identifying payload fields so
  an unrelated producer cannot fail the test.
  """

  use Credo.Check,
    base_priority: :high,
    category: :warning,
    explanations: [
      check: """
      Globally subscribed PubSub events must not use wildcard payloads in
      refute_receive. Pin the event's test-specific identity instead.
      """
    ]

  alias Credo.{Code, IssueMeta}

  @global_subscription_tags %{
    subscribe_dispatch: [:dispatch_complete, :dispatch_fallthrough],
    subscribe_mcp: [:mcp_delivery_dropped, :mcp_handler_registered]
  }

  @doc false
  @spec run(Credo.SourceFile.t(), keyword()) :: [Credo.Issue.t()]
  def run(%{filename: filename} = source_file, params \\ []) do
    if test_file?(filename) do
      issue_meta = IssueMeta.for(source_file, params)
      subscribed_tags = globally_subscribed_tags(source_file)
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

  defp globally_subscribed_tags(source_file) do
    Code.prewalk(
      source_file,
      fn
        {{:., _dot_meta, [_module, function]}, _call_meta, []} = ast, tags ->
          subscribed = Map.get(@global_subscription_tags, function, [])
          {ast, Enum.reduce(subscribed, tags, &MapSet.put(&2, &1))}

        ast, tags ->
          {ast, tags}
      end,
      MapSet.new()
    )
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
