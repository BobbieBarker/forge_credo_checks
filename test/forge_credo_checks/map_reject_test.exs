defmodule ForgeCredoChecks.MapRejectTest do
  use Credo.Test.Case

  alias ForgeCredoChecks.MapReject

  test "no issue: plain map alone" do
    """
    defmodule Sample do
      def go(things), do: Enum.map(things, &transform/1)
    end
    """
    |> to_source_file()
    |> run_check(MapReject)
    |> refute_issues()
  end

  test "no issue: reject |> map (different rule)" do
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
    |> run_check(MapReject)
    |> refute_issues()
  end

  test "issue: pipe shape" do
    """
    defmodule Sample do
      def go(things) do
        things
        |> Enum.map(&transform/1)
        |> Enum.reject(&drop?/1)
      end
    end
    """
    |> to_source_file()
    |> run_check(MapReject)
    |> assert_issue()
  end

  test "issue: nested call shape" do
    """
    defmodule Sample do
      def go(things), do: Enum.reject(Enum.map(things, &transform/1), &drop?/1)
    end
    """
    |> to_source_file()
    |> run_check(MapReject)
    |> assert_issue()
  end

  test "issue: longer pipe chain" do
    """
    defmodule Sample do
      def go(things) do
        things
        |> Stream.uniq()
        |> Enum.map(&transform/1)
        |> Enum.reject(&drop?/1)
      end
    end
    """
    |> to_source_file()
    |> run_check(MapReject)
    |> assert_issue()
  end
end
