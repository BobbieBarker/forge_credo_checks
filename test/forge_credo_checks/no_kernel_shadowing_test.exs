defmodule ForgeCredoChecks.NoKernelShadowingTest do
  use Credo.Test.Case

  alias ForgeCredoChecks.NoKernelShadowing

  test "no issue: descriptive variable names" do
    """
    defmodule Sample do
      def f(list) do
        Enum.reduce(list, 0, fn x, current_max -> max(current_max, x) end)
      end
    end
    """
    |> to_source_file()
    |> run_check(NoKernelShadowing)
    |> refute_issues()
  end

  test "no issue: Kernel function calls (not bindings) are fine" do
    """
    defmodule Sample do
      def f(a, b) do
        max(a, b)
      end
    end
    """
    |> to_source_file()
    |> run_check(NoKernelShadowing)
    |> refute_issues()
  end

  test "issue: max as fn parameter" do
    """
    defmodule Sample do
      def f(list) do
        Enum.reduce(list, 0, fn x, max -> max(max, x) end)
      end
    end
    """
    |> to_source_file()
    |> run_check(NoKernelShadowing)
    |> assert_issue()
  end

  test "issue: length as def parameter" do
    """
    defmodule Sample do
      defp truncate(string, length) do
        String.slice(string, 0, length)
      end
    end
    """
    |> to_source_file()
    |> run_check(NoKernelShadowing)
    |> assert_issue()
  end

  test "issue: min in a match" do
    """
    defmodule Sample do
      def f do
        min = 0
        min
      end
    end
    """
    |> to_source_file()
    |> run_check(NoKernelShadowing)
    |> assert_issue()
  end

  test "issue: multiple shadowed names produce multiple issues" do
    """
    defmodule Sample do
      def f(list) do
        Enum.reduce(list, {0, 100}, fn x, {max, min} -> {max(max, x), min(min, x)} end)
      end
    end
    """
    |> to_source_file()
    |> run_check(NoKernelShadowing)
    |> assert_issues(fn issues -> assert length(issues) == 2 end)
  end
end
