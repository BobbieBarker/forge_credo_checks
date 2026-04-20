defmodule ForgeCredoChecks.SortListFirstTest do
  use Credo.Test.Case

  alias ForgeCredoChecks.SortListFirst

  describe "no issue" do
    test "Enum.min directly" do
      """
      defmodule Sample do
        def go(xs), do: Enum.min(xs)
      end
      """
      |> to_source_file()
      |> run_check(SortListFirst)
      |> refute_issues()
    end

    test "Enum.sort alone" do
      """
      defmodule Sample do
        def go(xs), do: Enum.sort(xs)
      end
      """
      |> to_source_file()
      |> run_check(SortListFirst)
      |> refute_issues()
    end

    test "Enum.sort |> Enum.take(50)" do
      """
      defmodule Sample do
        def go(xs), do: xs |> Enum.sort() |> Enum.take(50)
      end
      """
      |> to_source_file()
      |> run_check(SortListFirst)
      |> refute_issues()
    end
  end

  describe "issue" do
    test "Enum.sort |> List.first" do
      """
      defmodule Sample do
        def go(xs), do: xs |> Enum.sort() |> List.first()
      end
      """
      |> to_source_file()
      |> run_check(SortListFirst)
      |> assert_issue()
    end

    test "Enum.sort(:desc) |> List.first" do
      """
      defmodule Sample do
        def go(xs), do: xs |> Enum.sort(:desc) |> List.first()
      end
      """
      |> to_source_file()
      |> run_check(SortListFirst)
      |> assert_issue()
    end

    test "Enum.sort_by(f) |> List.first" do
      """
      defmodule Sample do
        def go(xs), do: xs |> Enum.sort_by(& &1.score) |> List.first()
      end
      """
      |> to_source_file()
      |> run_check(SortListFirst)
      |> assert_issue()
    end

    test "Enum.sort_by(f, :desc) |> List.last" do
      """
      defmodule Sample do
        def go(xs), do: xs |> Enum.sort_by(& &1.score, :desc) |> List.last()
      end
      """
      |> to_source_file()
      |> run_check(SortListFirst)
      |> assert_issue()
    end

    test "List.first(Enum.sort(xs))" do
      """
      defmodule Sample do
        def go(xs), do: List.first(Enum.sort(xs))
      end
      """
      |> to_source_file()
      |> run_check(SortListFirst)
      |> assert_issue()
    end
  end
end
