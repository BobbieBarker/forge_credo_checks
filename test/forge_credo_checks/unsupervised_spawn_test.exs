defmodule ForgeCredoChecks.UnsupervisedSpawnTest do
  use Credo.Test.Case

  alias ForgeCredoChecks.UnsupervisedSpawn

  test "issue: spawn/1 with a closure" do
    """
    defmodule Sample do
      def go, do: spawn(fn -> work() end)
    end
    """
    |> to_source_file()
    |> run_check(UnsupervisedSpawn)
    |> assert_issue()
  end

  test "issue: spawn_link/3 mfa" do
    """
    defmodule Sample do
      def go(state), do: spawn_link(MyMod, :loop, [state])
    end
    """
    |> to_source_file()
    |> run_check(UnsupervisedSpawn)
    |> assert_issue()
  end

  test "issue: spawn_monitor and Process.spawn" do
    """
    defmodule Sample do
      def a, do: spawn_monitor(fn -> work() end)
      def b, do: Process.spawn(fn -> work() end, [])
    end
    """
    |> to_source_file()
    |> run_check(UnsupervisedSpawn)
    |> assert_issues()
  end

  test "no issue: Task.Supervisor and DynamicSupervisor are supervised" do
    """
    defmodule Sample do
      def a, do: Task.Supervisor.start_child(MyApp.Sup, fn -> work() end)
      def b, do: DynamicSupervisor.start_child(MyApp.Sup, {Worker, arg})
    end
    """
    |> to_source_file()
    |> run_check(UnsupervisedSpawn)
    |> refute_issues()
  end

  test "no issue: Task.start is not flagged by this check" do
    """
    defmodule Sample do
      def a, do: Task.start(fn -> work() end)
    end
    """
    |> to_source_file()
    |> run_check(UnsupervisedSpawn)
    |> refute_issues()
  end

  test "no issue: spawn in a path matched by :excluded_paths" do
    """
    defmodule Sample do
      def go, do: spawn(fn -> work() end)
    end
    """
    |> to_source_file("test/sample_test.exs")
    |> run_check(UnsupervisedSpawn, excluded_paths: [~r/_test\.exs$/])
    |> refute_issues()
  end

  test "issue: spawn still flagged in a path not matched by :excluded_paths" do
    """
    defmodule Sample do
      def go, do: spawn(fn -> work() end)
    end
    """
    |> to_source_file("lib/sample.ex")
    |> run_check(UnsupervisedSpawn, excluded_paths: [~r/_test\.exs$/])
    |> assert_issue()
  end
end
