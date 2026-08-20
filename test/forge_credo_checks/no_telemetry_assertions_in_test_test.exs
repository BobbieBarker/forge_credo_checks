defmodule ForgeCredoChecks.NoTelemetryAssertionsInTestTest do
  @moduledoc false

  use Credo.Test.Case, async: true

  alias ForgeCredoChecks.NoTelemetryAssertionsInTest

  setup_all do
    assert {:ok, _started} = Application.ensure_all_started(:credo)
    :ok
  end

  test "flags telemetry attachment in a test file" do
    source = telemetry_attach_source()

    assert [issue] = execute_check(source, "test/example_test.exs")
    assert issue.trigger === ":telemetry.attach"
  end

  test "flags assert_received containing an event under a default telemetry root" do
    source =
      "assert_received {:telemetry, [:forge_symphony, :dispatch, :complete], %{}, %{}}"

    assert [issue] = execute_check(source, "test/example_test.exs")
    assert issue.trigger === "assert_received"
  end

  test "flags telemetry_test attachment helpers" do
    source =
      Enum.join([
        ":telemetry_test.",
        "attach_event_handlers(self(), [[:dispatch_budget, :lease_released]])"
      ])

    assert [issue] = execute_check(source, "test/example_test.exs")
    assert issue.trigger === ":telemetry_test.attach_event_handlers"
  end

  test "flags telemetry event-name lists under a default root" do
    source =
      "assert_receive {[:dispatch_admission, :grant], ref, %{count: 1}, %{class: :normal}}"

    assert [issue] = execute_check(source, "test/example_test.exs")
    assert issue.trigger === "assert_receive"
  end

  test "flags an event whose root is supplied through check parameters" do
    source = "refute_receive {[:pr_tracker, :ci, :failed], %{}, %{pr: 42}, %{}}"

    assert [issue] =
             execute_check(source, "test/example_test.exs", telemetry_event_roots: [:pr_tracker])

    assert issue.trigger === "refute_receive"
  end

  test "allows an event whose root is omitted from configured check parameters" do
    source = "assert_receive {[:dispatch_budget, :lease_released], %{}, %{lease: 1}, %{}}"

    assert [] =
             execute_check(source, "test/example_test.exs", telemetry_event_roots: [:pr_tracker])
  end

  test "an omitted configured root does not erase an earlier telemetry match" do
    source = """
    assert_received {:batch,
      [
        {:telemetry, [:any_app, :event], %{}, %{}},
        {[:dispatch_budget, :lease_released], %{}, %{}, %{}}
      ]}
    """

    assert [issue] =
             execute_check(source, "test/example_test.exs", telemetry_event_roots: [:pr_tracker])

    assert issue.trigger === "assert_received"
  end

  test "flags an event name lifted into a module attribute" do
    source = """
    defmodule ExampleTest do
      @event [:forge_symphony, :dispatch, :complete]

      def assert_it do
        assert_receive {@event, _ref, %{}, %{}}
      end
    end
    """

    assert [issue] = execute_check(source, "test/example_test.exs")
    assert issue.trigger === "assert_receive"
  end

  test "allows a module-attribute event whose root is not configured" do
    source = """
    defmodule ExampleTest do
      @event [:other_app, :dispatch, :complete]

      def assert_it do
        assert_receive {@event, _ref, %{}, %{}}
      end
    end
    """

    assert [] = execute_check(source, "test/example_test.exs")
  end

  test "flags telemetry attachment routed through apply/3" do
    source =
      Enum.join([
        "apply(:telemetry, :attach, ",
        "[\"handler\", [:app, :event], &handle/4, nil])"
      ])

    assert [issue] = execute_check(source, "test/example_test.exs")
    assert issue.trigger === ":telemetry.attach"
  end

  test "flags telemetry_test attachment routed through apply/3" do
    source =
      Enum.join([
        "apply(:telemetry_test, :attach_event_handlers, ",
        "[self(), [[:dispatch_budget, :lease_released]]])"
      ])

    assert [issue] = execute_check(source, "test/example_test.exs")
    assert issue.trigger === ":telemetry_test.attach_event_handlers"
  end

  test "flags a two-element telemetry-tagged message" do
    source = "assert_received {:telemetry, payload}"

    assert [issue] = execute_check(source, "test/example_test.exs")
    assert issue.trigger === "assert_received"
  end

  test "flags a two-element message carrying a telemetry event name" do
    source = "refute_receive {[:forge_reactor, :step, :stop], measurements}"

    assert [issue] = execute_check(source, "test/example_test.exs")
    assert issue.trigger === "refute_receive"
  end

  test "allows apply/3 to an unrelated module" do
    source = "apply(MyApp.Worker, :attach, [\"handler\", [:app, :event]])"

    assert [] = execute_check(source, "test/example_test.exs")
  end

  test "allows assert_received on a normal message" do
    source = "assert_received {:dispatch_complete, slot_id}"

    assert [] = execute_check(source, "test/example_test.exs")
  end

  test "allows PubSub contract events that retain the original event name" do
    source =
      "assert_received {:reactor_event, [:forge_reactor, :step, :stop], %{}, %{}}"

    assert [] = execute_check(source, "test/example_test.exs")
  end

  test "allows telemetry attachment in production code" do
    source = telemetry_attach_source()

    assert [] = execute_check(source, "lib/example.ex")
  end

  test "flags telemetry attachment when Credo supplies an absolute test filename" do
    filename = Path.join([File.cwd!(), "test", "example_test.exs"])

    assert [_issue] = execute_check(telemetry_attach_source(), filename)
  end

  defp execute_check(source, filename, params \\ []) do
    source
    |> to_source_file(filename)
    |> NoTelemetryAssertionsInTest.run(params)
  end

  defp telemetry_attach_source do
    ":telemetry." <> "attach(\"handler\", [:app, :event], &handle/4, nil)"
  end
end
