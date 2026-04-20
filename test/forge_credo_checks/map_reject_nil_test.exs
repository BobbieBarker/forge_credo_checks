defmodule ForgeCredoChecks.MapRejectNilTest do
  use Credo.Test.Case

  alias ForgeCredoChecks.MapRejectNil

  describe "no issue" do
    test "map alone" do
      """
      defmodule Sample do
        def go(things), do: Enum.map(things, &parse/1)
      end
      """
      |> to_source_file()
      |> run_check(MapRejectNil)
      |> refute_issues()
    end

    test "map |> reject with non-is-nil predicate is not flagged here" do
      """
      defmodule Sample do
        def go(things) do
          things
          |> Enum.map(&parse/1)
          |> Enum.reject(&(&1.score < 0))
        end
      end
      """
      |> to_source_file()
      |> run_check(MapRejectNil)
      |> refute_issues()
    end
  end

  describe "issue" do
    test "capture syntax `&is_nil/1`" do
      """
      defmodule Sample do
        def go(things) do
          things
          |> Enum.map(&parse/1)
          |> Enum.reject(&is_nil/1)
        end
      end
      """
      |> to_source_file()
      |> run_check(MapRejectNil)
      |> assert_issue()
    end

    test "capture-arg form `&(&1 == nil)`" do
      """
      defmodule Sample do
        def go(things) do
          things
          |> Enum.map(&parse/1)
          |> Enum.reject(&(&1 == nil))
        end
      end
      """
      |> to_source_file()
      |> run_check(MapRejectNil)
      |> assert_issue()
    end

    test "capture-arg form `&(&1 === nil)`" do
      """
      defmodule Sample do
        def go(things) do
          things
          |> Enum.map(&parse/1)
          |> Enum.reject(&(&1 === nil))
        end
      end
      """
      |> to_source_file()
      |> run_check(MapRejectNil)
      |> assert_issue()
    end

    test "anonymous fn `fn x -> is_nil(x) end`" do
      """
      defmodule Sample do
        def go(things) do
          things
          |> Enum.map(&parse/1)
          |> Enum.reject(fn x -> is_nil(x) end)
        end
      end
      """
      |> to_source_file()
      |> run_check(MapRejectNil)
      |> assert_issue()
    end

    test "anonymous fn `fn x -> x == nil end`" do
      """
      defmodule Sample do
        def go(things) do
          things
          |> Enum.map(&parse/1)
          |> Enum.reject(fn x -> x == nil end)
        end
      end
      """
      |> to_source_file()
      |> run_check(MapRejectNil)
      |> assert_issue()
    end

    test "nested call shape with &is_nil/1" do
      """
      defmodule Sample do
        def go(things), do: Enum.reject(Enum.map(things, &parse/1), &is_nil/1)
      end
      """
      |> to_source_file()
      |> run_check(MapRejectNil)
      |> assert_issue()
    end
  end
end
