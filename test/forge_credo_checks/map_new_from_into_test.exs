defmodule ForgeCredoChecks.MapNewFromIntoTest do
  use Credo.Test.Case

  alias ForgeCredoChecks.MapNewFromInto

  describe "no issue" do
    test "Map.new/2 directly is fine" do
      """
      defmodule Sample do
        def go(xs), do: Map.new(xs, fn {k, v} -> {String.downcase(k), v} end)
      end
      """
      |> to_source_file()
      |> run_check(MapNewFromInto)
      |> refute_issues()
    end

    test "Enum.into into a non-empty map is not flagged" do
      """
      defmodule Sample do
        def go(xs, base), do: Enum.into(xs, base, fn {k, v} -> {k, v} end)
      end
      """
      |> to_source_file()
      |> run_check(MapNewFromInto)
      |> refute_issues()
    end

    test "Enum.into without a transform fn (the MapInto stock check territory)" do
      """
      defmodule Sample do
        def go(xs), do: Enum.into(xs, %{})
      end
      """
      |> to_source_file()
      |> run_check(MapNewFromInto)
      |> refute_issues()
    end
  end

  describe "issue" do
    test "direct call form" do
      """
      defmodule Sample do
        def go(xs), do: Enum.into(xs, %{}, fn {k, v} -> {String.downcase(k), v} end)
      end
      """
      |> to_source_file()
      |> run_check(MapNewFromInto)
      |> assert_issue()
    end

    test "pipe form" do
      """
      defmodule Sample do
        def go(xs) do
          xs |> Enum.into(%{}, fn {k, v} -> {String.downcase(k), v} end)
        end
      end
      """
      |> to_source_file()
      |> run_check(MapNewFromInto)
      |> assert_issue()
    end
  end
end
