defmodule ForgeCredoChecks.TelemetryControlFlowTest do
  use Credo.Test.Case

  alias ForgeCredoChecks.TelemetryControlFlow

  test "issue: :telemetry.attach with an inline handler that calls GenServer.cast" do
    """
    defmodule Sample do
      def attach do
        :telemetry.attach("handler", [:app, :event], fn _, _, _, _ ->
          GenServer.cast(pid, :adjust)
        end, nil)
      end
    end
    """
    |> to_source_file("lib/sample.ex")
    |> run_check(TelemetryControlFlow)
    |> assert_issue(%{trigger: "GenServer.cast"})
  end

  test "issue: inline handler that calls send/2" do
    """
    defmodule Sample do
      def attach do
        :telemetry.attach("handler", [:app, :event], fn _, _, _, _ ->
          send(pid, :tick)
        end, nil)
      end
    end
    """
    |> to_source_file("lib/sample.ex")
    |> run_check(TelemetryControlFlow)
    |> assert_issue(%{trigger: "send"})
  end

  test "issue: inline handler that calls GenServer.call" do
    """
    defmodule Sample do
      def attach do
        :telemetry.attach("handler", [:app, :event], fn _, _, _, _ ->
          GenServer.call(server, :query)
        end, nil)
      end
    end
    """
    |> to_source_file("lib/sample.ex")
    |> run_check(TelemetryControlFlow)
    |> assert_issue(%{trigger: "GenServer.call"})
  end

  test "issue: :telemetry.attach_many with a control-flow inline handler" do
    """
    defmodule Sample do
      def attach do
        :telemetry.attach_many("handler", [[:a, :b], [:c, :d]], fn _, _, _, _ ->
          GenServer.cast(pid, :go)
        end, nil)
      end
    end
    """
    |> to_source_file("lib/sample.ex")
    |> run_check(TelemetryControlFlow)
    |> assert_issue(%{trigger: "GenServer.cast"})
  end

  test "no issue: observation-only inline handler (Logger.info)" do
    """
    defmodule Sample do
      def attach do
        :telemetry.attach("handler", [:app, :event], fn _, _, _, _ ->
          Logger.info("event observed")
        end, nil)
      end
    end
    """
    |> to_source_file("lib/sample.ex")
    |> run_check(TelemetryControlFlow)
    |> refute_issues()
  end

  test "no issue: observation-only inline handler (metric emission via :telemetry.execute)" do
    """
    defmodule Sample do
      def attach do
        :telemetry.attach("handler", [:app, :event], fn _, _, _, _ ->
          :telemetry.execute([:app, :metric], %{}, %{})
        end, nil)
      end
    end
    """
    |> to_source_file("lib/sample.ex")
    |> run_check(TelemetryControlFlow)
    |> refute_issues()
  end

  test "no issue: observation-only inline handler (span recording)" do
    """
    defmodule Sample do
      def attach do
        :telemetry.attach("handler", [:app, :event], fn _event, measures, _meta, _conf ->
          :ets.insert(:spans, {System.monotonic_time(), measures})
        end, nil)
      end
    end
    """
    |> to_source_file("lib/sample.ex")
    |> run_check(TelemetryControlFlow)
    |> refute_issues()
  end

  test "no issue: named MFA-tuple handler is out of scope for this pass" do
    """
    defmodule Sample do
      def attach do
        :telemetry.attach("handler", [:app, :event], {MyMod, :handle_event, nil}, nil)
      end
    end
    """
    |> to_source_file("lib/sample.ex")
    |> run_check(TelemetryControlFlow)
    |> refute_issues()
  end

  test "no issue: control-flow handler in a file matched by :excluded_paths" do
    """
    defmodule Sample do
      def attach do
        :telemetry.attach("handler", [:app, :event], fn _, _, _, _ ->
          GenServer.cast(pid, :go)
        end, nil)
      end
    end
    """
    |> to_source_file("lib/legacy/telemetry_bridge.ex")
    |> run_check(TelemetryControlFlow, excluded_paths: [~r"^lib/legacy/"])
    |> refute_issues()
  end

  test "issue: control-flow handler still flagged when excluded_paths does not match" do
    """
    defmodule Sample do
      def attach do
        :telemetry.attach("handler", [:app, :event], fn _, _, _, _ ->
          GenServer.cast(pid, :go)
        end, nil)
      end
    end
    """
    |> to_source_file("lib/legacy/telemetry_bridge.ex")
    |> run_check(TelemetryControlFlow, excluded_paths: [~r"^test/"])
    |> assert_issue()
  end

  test "no issue: control-flow call outside any telemetry handler is not flagged" do
    """
    defmodule Sample do
      def go, do: GenServer.cast(pid, :go)
    end
    """
    |> to_source_file("lib/sample.ex")
    |> run_check(TelemetryControlFlow)
    |> refute_issues()
  end

  test "no issue: :telemetry.attach with a non-fn handler arg (variable) is out of scope" do
    """
    defmodule Sample do
      def attach(handler) do
        :telemetry.attach("handler", [:app, :event], handler, nil)
      end
    end
    """
    |> to_source_file("lib/sample.ex")
    |> run_check(TelemetryControlFlow)
    |> refute_issues()
  end

  test "issue: :erlang.send inside an inline handler is flagged" do
    """
    defmodule Sample do
      def attach do
        :telemetry.attach("handler", [:app, :event], fn _, _, _, _ ->
          :erlang.send(pid, :tick)
        end, nil)
      end
    end
    """
    |> to_source_file("lib/sample.ex")
    |> run_check(TelemetryControlFlow)
    |> assert_issue(%{trigger: ":erlang.send"})
  end

  test "issue message names the control-flow call and points at the telemetry attach site" do
    issue =
      """
      defmodule Sample do
        def attach do
          :telemetry.attach("handler", [:app, :event], fn _, _, _, _ ->
            GenServer.cast(pid, :go)
          end, nil)
        end
      end
      """
      |> to_source_file("lib/sample.ex")
      |> run_check(TelemetryControlFlow)
      |> assert_issue()
      |> List.first()

    assert issue.message =~ "telemetry"
    assert issue.message =~ "GenServer.cast"
    assert issue.message =~ "observation-only"
  end

  test "no issue: :telemetry.detach and other telemetry calls without an inline handler are not flagged" do
    """
    defmodule Sample do
      def detach do
        :telemetry.detach("handler")
      end
    end
    """
    |> to_source_file("lib/sample.ex")
    |> run_check(TelemetryControlFlow)
    |> refute_issues()
  end
end
