defmodule ForgeCredoChecks.TimingAndPrivateStateGuardTest do
  use Credo.Test.Case

  alias ForgeCredoChecks.TimingAndPrivateStateGuard

  test "issue: Process.sleep/1 call node" do
    issue =
      """
      defmodule TimingTest do
        def wait_for_work do
          Process.sleep(10)
        end
      end
      """
      |> to_source_file("test/anubis/timing_test.exs")
      |> run_check(TimingAndPrivateStateGuard)
      |> assert_issue(%{trigger: "Process.sleep", line_no: 3})
      |> List.first()

    assert issue.message =~ "`Process.sleep`"
    assert issue.message =~ "contracts/template_variables_contract_test.exs"
    assert issue.message =~ "string"
    assert issue.message =~ "atom"
    assert issue.message =~ ":excluded_paths"
  end

  test "issue: :sys.replace_state/2 call node" do
    issue =
      """
      defmodule PrivateStateTest do
        def force_state(pid, state) do
          :sys.replace_state(pid, fn _old -> state end)
        end
      end
      """
      |> to_source_file("test/anubis/private_state_test.exs")
      |> run_check(TimingAndPrivateStateGuard)
      |> assert_issue(%{trigger: ":sys.replace_state", line_no: 3})
      |> List.first()

    assert issue.message =~ "`:sys.replace_state`"
    assert issue.message =~ "contracts/template_variables_contract_test.exs"
  end

  test "no issue: string and atom literals are not call nodes" do
    """
    defmodule LiteralMentionTest do
      @sleep_text "Process.sleep(10)"
      @replace_text ":sys.replace_state(pid, fun)"
      @sleep_atom :"Process.sleep"
      @replace_atom :"sys.replace_state"

      def mentions do
        {@sleep_text, @replace_text, @sleep_atom, @replace_atom, :sys, :replace_state}
      end
    end
    """
    |> to_source_file("test/anubis/literal_mention_test.exs")
    |> run_check(TimingAndPrivateStateGuard)
    |> refute_issues()
  end

  test "no issue: source-grep sentinel content =~ string does not self-flag" do
    """
    defmodule AdrRulesTest do
      def check(content) do
        assert content =~ ":sys.replace_state"
      end
    end
    """
    |> to_source_file("framework/adr_rules_test.exs")
    |> run_check(TimingAndPrivateStateGuard)
    |> refute_issues()
  end

  test "no issue: function captures only mention the guarded calls" do
    """
    defmodule CaptureMentionTest do
      def callbacks do
        {&Process.sleep/1, &:sys.replace_state/2, &Process.sleep(&1)}
      end
    end
    """
    |> to_source_file("test/anubis/capture_mention_test.exs")
    |> run_check(TimingAndPrivateStateGuard)
    |> refute_issues()
  end

  test "no issue: excluded_paths skips migration-bridge files" do
    """
    defmodule LegacyTimingTest do
      def wait_for_work do
        Process.sleep(10)
      end
    end
    """
    |> to_source_file("test/legacy_timing/timing_test.exs")
    |> run_check(TimingAndPrivateStateGuard, excluded_paths: [~r"^test/legacy_timing/"])
    |> refute_issues()
  end

  test "issue: not skipped when excluded_paths does not match" do
    """
    defmodule LegacyTimingTest do
      def wait_for_work do
        Process.sleep(10)
      end
    end
    """
    |> to_source_file("test/legacy_timing/timing_test.exs")
    |> run_check(TimingAndPrivateStateGuard, excluded_paths: [~r"^test/other/"])
    |> assert_issue(%{trigger: "Process.sleep"})
  end
end
