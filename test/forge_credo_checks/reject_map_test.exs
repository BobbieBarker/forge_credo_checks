defmodule ForgeCredoChecks.RejectMapTest do
  use Credo.Test.Case

  alias ForgeCredoChecks.RejectMap

  test "no issue: plain map alone" do
    """
    defmodule Sample do
      def go(things), do: Enum.map(things, &transform/1)
    end
    """
    |> to_source_file()
    |> run_check(RejectMap)
    |> refute_issues()
  end

  test "no issue: filter |> map (different rule)" do
    """
    defmodule Sample do
      def go(things) do
        things
        |> Enum.filter(&keep?/1)
        |> Enum.map(&transform/1)
      end
    end
    """
    |> to_source_file()
    |> run_check(RejectMap)
    |> refute_issues()
  end

  test "issue: pipe shape" do
    """
    defmodule Sample do
      def go(things) do
        things
        |> Enum.reject(&drop?/1)
        |> Enum.map(&transform/1)
      end
    end
    """
    |> to_source_file()
    |> run_check(RejectMap)
    |> assert_issue()
  end

  test "issue: nested call shape" do
    """
    defmodule Sample do
      def go(things), do: Enum.map(Enum.reject(things, &drop?/1), &transform/1)
    end
    """
    |> to_source_file()
    |> run_check(RejectMap)
    |> assert_issue()
  end
end
