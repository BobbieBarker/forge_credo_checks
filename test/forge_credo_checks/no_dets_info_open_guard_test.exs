defmodule ForgeCredoChecks.NoDetsInfoOpenGuardTest do
  @moduledoc false

  use Credo.Test.Case, async: true

  alias ForgeCredoChecks.NoDetsInfoOpenGuard

  setup_all do
    assert {:ok, _started} = Application.ensure_all_started(:credo)
    :ok
  end

  test "flags arity-one dets info comparisons against undefined in lib files" do
    assert [issue] = execute_check(flagged_source())
    assert issue.trigger === ":dets.info/1"
  end

  test "flags reversed undefined comparisons in lib files" do
    source = """
    defmodule Example do
      def open(table) do
        if :undefined == :dets.info(table), do: :missing, else: :open
      end
    end
    """

    assert [issue] = execute_check(source)
    assert issue.trigger === ":dets.info/1"
  end

  test "flags direct case matches against undefined in lib files" do
    source = """
    defmodule Example do
      def open(table) do
        case :dets.info(table) do
          :undefined -> :dets.open_file(table, [])
          _ -> {:ok, table}
        end
      end
    end
    """

    assert [issue] = execute_check(source)
    assert issue.trigger === ":dets.info/1"
  end

  test "flags a comparison against a variable bound to the info call" do
    source = """
    defmodule Example do
      def open(table) do
        info = :dets.info(table)

        if info !== :undefined, do: {:ok, table}, else: :dets.open_file(table, [])
      end
    end
    """

    assert [issue] = execute_check(source)
    assert issue.trigger === ":dets.info/1"
  end

  test "flags a case on a variable bound to the info call" do
    source = """
    defmodule Example do
      def open(table) do
        info = :dets.info(table)

        case info do
          :undefined -> :dets.open_file(table, [])
          _ -> {:ok, table}
        end
      end
    end
    """

    assert [issue] = execute_check(source)
    assert issue.trigger === ":dets.info/1"
  end

  test "allows a variable bound to an arity-two info call" do
    source = """
    defmodule Example do
      def size(table) do
        size = :dets.info(table, :size)

        size !== :undefined
      end
    end
    """

    assert [] = execute_check(source)
  end

  test "allows a variable bound to the info call and compared against another value" do
    source = """
    defmodule Example do
      def open(table) do
        info = :dets.info(table)

        info !== :open
      end
    end
    """

    assert [] = execute_check(source)
  end

  test "allows a rebound variable whose second value is not an info call" do
    source = """
    defmodule Example do
      def open(table, fallback) do
        info = :dets.info(table)
        info = fallback

        info !== :undefined
      end
    end
    """

    assert [] = execute_check(source)
  end

  test "does not carry a binding into a sibling function body" do
    source = """
    defmodule Example do
      def open(table) do
        info = :dets.info(table)
        {:ok, info}
      end

      def stale?(info) do
        info !== :undefined
      end
    end
    """

    assert [] = execute_check(source)
  end

  test "allows arity-two info calls and non-undefined comparisons" do
    source = """
    defmodule Example do
      def metadata(table) do
        {
          :dets.info(table, :size) !== :undefined,
          :dets.info(table) !== :open
        }
      end
    end
    """

    assert [] = execute_check(source)
  end

  test "ignores non-lib and nil filenames" do
    assert [] = execute_check(flagged_source(), "test/example_test.exs")

    source_file =
      flagged_source()
      |> to_source_file("lib/example.ex")
      |> Map.put(:filename, nil)

    assert [] = NoDetsInfoOpenGuard.run(source_file)
  end

  defp execute_check(source, filename \\ "lib/example.ex") do
    source
    |> to_source_file(filename)
    |> NoDetsInfoOpenGuard.run([])
  end

  defp flagged_source do
    """
    defmodule Example do
      def open(table) do
        if :dets.info(table) !== :undefined do
          {:ok, table}
        else
          :dets.open_file(table, [])
        end
      end
    end
    """
  end
end
