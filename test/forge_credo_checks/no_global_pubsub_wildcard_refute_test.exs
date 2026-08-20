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

  test "ignores production files" do
    source = """
    Events.subscribe_mcp()
    refute_receive {:mcp_delivery_dropped, _metadata}, 50
    """

    assert [] = execute_check(source, "lib/example.ex")
  end

  defp execute_check(source, filename \\ "test/example_test.exs") do
    source
    |> to_source_file(filename)
    |> NoGlobalPubSubWildcardRefute.run([])
  end
end
