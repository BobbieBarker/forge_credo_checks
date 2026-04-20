defmodule ForgeCredoChecks.MapNewFromReduceTest do
  use Credo.Test.Case

  alias ForgeCredoChecks.MapNewFromReduce

  describe "no issue" do
    test "Map.new/2 directly is fine" do
      """
      defmodule Sample do
        def go(xs), do: Map.new(xs, fn x -> {x.id, x} end)
      end
      """
      |> to_source_file()
      |> run_check(MapNewFromReduce)
      |> refute_issues()
    end

    test "reduce into a non-map accumulator is not flagged" do
      """
      defmodule Sample do
        def go(xs), do: Enum.reduce(xs, [], fn x, acc -> [x | acc] end)
      end
      """
      |> to_source_file()
      |> run_check(MapNewFromReduce)
      |> refute_issues()
    end

    test "reduce with a non-Map.put body is not flagged" do
      """
      defmodule Sample do
        def go(xs) do
          Enum.reduce(xs, %{}, fn x, acc ->
            Map.update(acc, x.id, [x], &[x | &1])
          end)
        end
      end
      """
      |> to_source_file()
      |> run_check(MapNewFromReduce)
      |> refute_issues()
    end

    test "reduce that calls Map.put on a different binding is not flagged" do
      """
      defmodule Sample do
        def go(xs, other) do
          Enum.reduce(xs, %{}, fn _x, _acc -> Map.put(other, :a, 1) end)
        end
      end
      """
      |> to_source_file()
      |> run_check(MapNewFromReduce)
      |> refute_issues()
    end
  end

  describe "issue" do
    test "direct call form with arbitrary acc binding name" do
      """
      defmodule Sample do
        def go(xs) do
          Enum.reduce(xs, %{}, fn x, acc -> Map.put(acc, x.id, x) end)
        end
      end
      """
      |> to_source_file()
      |> run_check(MapNewFromReduce)
      |> assert_issue()
    end

    test "alternative acc binding name (m, result, etc.)" do
      """
      defmodule Sample do
        def go(xs) do
          Enum.reduce(xs, %{}, fn x, m -> Map.put(m, x.id, transform(x)) end)
        end
      end
      """
      |> to_source_file()
      |> run_check(MapNewFromReduce)
      |> assert_issue()
    end

    test "pipe form" do
      """
      defmodule Sample do
        def go(xs) do
          xs |> Enum.reduce(%{}, fn x, acc -> Map.put(acc, x.id, x) end)
        end
      end
      """
      |> to_source_file()
      |> run_check(MapNewFromReduce)
      |> assert_issue()
    end
  end
end
