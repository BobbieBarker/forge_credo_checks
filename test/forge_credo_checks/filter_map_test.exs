defmodule ForgeCredoChecks.FilterMapTest do
  use Credo.Test.Case

  alias ForgeCredoChecks.FilterMap

  describe "no issue" do
    test "plain code without an Enum chain" do
      """
      defmodule Sample do
        def go(things), do: Enum.map(things, &transform/1)
      end
      """
      |> to_source_file()
      |> run_check(FilterMap)
      |> refute_issues()
    end

    test "filter alone is fine" do
      """
      defmodule Sample do
        def go(things), do: things |> Enum.filter(&keep?/1)
      end
      """
      |> to_source_file()
      |> run_check(FilterMap)
      |> refute_issues()
    end

    test "filter |> reject (different chain) is not flagged" do
      """
      defmodule Sample do
        def go(things) do
          things
          |> Enum.filter(&keep?/1)
          |> Enum.reject(&drop?/1)
        end
      end
      """
      |> to_source_file()
      |> run_check(FilterMap)
      |> refute_issues()
    end
  end

  describe "issue" do
    test "two-step pipe (shape 2)" do
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
      |> run_check(FilterMap)
      |> assert_issue()
    end

    test "direct nested call (shape 1)" do
      """
      defmodule Sample do
        def go(things), do: Enum.map(Enum.filter(things, &keep?/1), &transform/1)
      end
      """
      |> to_source_file()
      |> run_check(FilterMap)
      |> assert_issue()
    end

    test "partial pipe + call (shape 3)" do
      """
      defmodule Sample do
        def go(things), do: Enum.map(things |> Enum.filter(&keep?/1), &transform/1)
      end
      """
      |> to_source_file()
      |> run_check(FilterMap)
      |> assert_issue()
    end

    test "longer pipe chain (shape 4)" do
      """
      defmodule Sample do
        def go(things) do
          things
          |> Stream.uniq()
          |> Enum.filter(&keep?/1)
          |> Enum.map(&transform/1)
        end
      end
      """
      |> to_source_file()
      |> run_check(FilterMap)
      |> assert_issue()
    end
  end
end
