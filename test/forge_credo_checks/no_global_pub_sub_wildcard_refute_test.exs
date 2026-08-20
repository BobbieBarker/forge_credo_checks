defmodule ForgeCredoChecks.NoGlobalPubSubWildcardRefuteTest do
  @moduledoc false

  use Credo.Test.Case, async: true

  alias ForgeCredoChecks.NoGlobalPubSubWildcardRefute

  setup_all do
    assert {:ok, _started} = Application.ensure_all_started(:credo)
    :ok
  end

  test "flags a wildcard refute for a globally subscribed MCP event" do
    source = """
    Events.subscribe_mcp()
    refute_receive {:mcp_delivery_dropped, _metadata}, 50
    """

    assert [issue] = execute_check(source)
    assert issue.trigger === "refute_receive"
  end

  test "uses the default check parameters" do
    source_file =
      to_source_file(
        """
        Events.subscribe_dispatch()
        refute_receive {:dispatch_complete, _metadata}
        """,
        "test/default_params_test.exs"
      )

    assert [_issue] = NoGlobalPubSubWildcardRefute.run(source_file)
  end

  test "allows a refute that pins the delivery transport" do
    source = """
    Events.subscribe_mcp()
    refute_receive {:mcp_delivery_dropped, %{transport: ^transport}}, 50
    """

    assert [] = execute_check(source)
  end

  test "allows a wildcard refute when the subscription is scoped" do
    source = """
    Events.subscribe_dispatch(scope)
    refute_receive {:dispatch_fallthrough, _metadata}, 50
    """

    assert [] = execute_check(source)
  end

  test "flags an unbound payload variable that omits the leading underscore" do
    source = """
    Events.subscribe_mcp()
    refute_receive {:mcp_delivery_dropped, metadata}, 50
    """

    assert [issue] = execute_check(source)
    assert issue.trigger === "refute_receive"
  end

  test "flags refute_received on a globally subscribed event" do
    source = """
    Events.subscribe_mcp()
    refute_received {:mcp_delivery_dropped, _metadata}
    """

    assert [issue] = execute_check(source)
    assert issue.trigger === "refute_received"
  end

  test "flags a wildcard payload in a three-element event tuple" do
    source = """
    Events.subscribe_mcp()
    refute_receive {:mcp_delivery_dropped, _id, _metadata}, 50
    """

    assert [issue] = execute_check(source)
    assert issue.trigger === "refute_receive"
  end

  test "flags a subscription taken as a bare imported local call" do
    source = """
    subscribe_mcp()
    refute_receive {:mcp_delivery_dropped, _metadata}, 50
    """

    assert [issue] = execute_check(source)
    assert issue.trigger === "refute_receive"
  end

  test "allows a three-element tuple that pins an identifying element" do
    source = """
    Events.subscribe_mcp()
    refute_receive {:mcp_delivery_dropped, ^delivery_id, _metadata}, 50
    """

    assert [] = execute_check(source)
  end

  test "allows a payload that destructures an identifying field" do
    source = """
    Events.subscribe_mcp()
    refute_received {:mcp_delivery_dropped, %{transport: ^transport}}
    """

    assert [] = execute_check(source)
  end

  test "allows an event tag outside the configured subscriptions" do
    source = """
    Events.subscribe_mcp()
    refute_receive {:unrelated_event, _metadata}, 50
    """

    assert [] = execute_check(source)
  end

  test "flags only tags declared for the configured subscription" do
    source = """
    subscribe_orders()
    refute_receive {:order_placed, _metadata}, 50
    """

    assert [issue] =
             execute_check(source, "test/example_test.exs",
               global_subscriptions: [subscribe_orders: [:order_placed]]
             )

    assert issue.trigger === "refute_receive"
  end

  test "ignores a nil filename" do
    source_file =
      """
      Events.subscribe_mcp()
      refute_receive {:mcp_delivery_dropped, _metadata}, 50
      """
      |> to_source_file("test/example_test.exs")
      |> Map.put(:filename, nil)

    assert [] = NoGlobalPubSubWildcardRefute.run(source_file)
  end

  test "ignores production files" do
    source = """
    Events.subscribe_mcp()
    refute_receive {:mcp_delivery_dropped, _metadata}, 50
    """

    assert [] = execute_check(source, "lib/example.ex")
  end

  defp execute_check(source, filename \\ "test/example_test.exs", params \\ []) do
    source
    |> to_source_file(filename)
    |> NoGlobalPubSubWildcardRefute.run(params)
  end
end
