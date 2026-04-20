defmodule ForgeCredoChecks.ReverseListFirstTest do
  use Credo.Test.Case

  alias ForgeCredoChecks.ReverseListFirst

  describe "no issue" do
    test "List.last directly" do
      """
      defmodule Sample do
        def go(xs), do: List.last(xs)
      end
      """
      |> to_source_file()
      |> run_check(ReverseListFirst)
      |> refute_issues()
    end

    test "Enum.reverse alone" do
      """
      defmodule Sample do
        def go(xs), do: Enum.reverse(xs)
      end
      """
      |> to_source_file()
      |> run_check(ReverseListFirst)
      |> refute_issues()
    end

    test "List.first alone" do
      """
      defmodule Sample do
        def go(xs), do: List.first(xs)
      end
      """
      |> to_source_file()
      |> run_check(ReverseListFirst)
      |> refute_issues()
    end

    test "Enum.reverse |> Enum.find_value (different chain)" do
      """
      defmodule Sample do
        def go(xs), do: xs |> Enum.reverse() |> Enum.find_value(&match?(&1))
      end
      """
      |> to_source_file()
      |> run_check(ReverseListFirst)
      |> refute_issues()
    end
  end

  describe "issue" do
    test "two-step pipe" do
      """
      defmodule Sample do
        def go(xs), do: xs |> Enum.reverse() |> List.first()
      end
      """
      |> to_source_file()
      |> run_check(ReverseListFirst)
      |> assert_issue()
    end

    test "longer pipe chain" do
      """
      defmodule Sample do
        def go(xs) do
          xs
          |> Enum.filter(&keep?/1)
          |> Enum.reverse()
          |> List.first()
        end
      end
      """
      |> to_source_file()
      |> run_check(ReverseListFirst)
      |> assert_issue()
    end

    test "List.first wrapping a piped reverse" do
      """
      defmodule Sample do
        def go(xs), do: List.first(xs |> Enum.reverse())
      end
      """
      |> to_source_file()
      |> run_check(ReverseListFirst)
      |> assert_issue()
    end

    test "List.first wrapping a direct Enum.reverse call" do
      """
      defmodule Sample do
        def go(xs), do: List.first(Enum.reverse(xs))
      end
      """
      |> to_source_file()
      |> run_check(ReverseListFirst)
      |> assert_issue()
    end
  end
end
