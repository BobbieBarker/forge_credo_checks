defmodule ForgeCredoChecks.NoCaseTrueFalseTest do
  use Credo.Test.Case

  alias ForgeCredoChecks.NoCaseTrueFalse

  test "no issue: case on a plain variable (could be tristate)" do
    """
    defmodule Sample do
      def f(state) do
        case state do
          true -> 1
          false -> 2
        end
      end
    end
    """
    |> to_source_file()
    |> run_check(NoCaseTrueFalse)
    |> refute_issues()
  end

  test "no issue: case with non-boolean patterns" do
    """
    defmodule Sample do
      def f(x) do
        case rem(x, 2) do
          0 -> :even
          1 -> :odd
        end
      end
    end
    """
    |> to_source_file()
    |> run_check(NoCaseTrueFalse)
    |> refute_issues()
  end

  test "issue: case on comparison with true/false clauses" do
    """
    defmodule Sample do
      def f(n) do
        case rem(n, 2) == 0 do
          true -> :even
          false -> :odd
        end
      end
    end
    """
    |> to_source_file()
    |> run_check(NoCaseTrueFalse)
    |> assert_issue()
  end

  test "issue: case on function call with false/true clause order" do
    """
    defmodule Sample do
      def f(x) do
        case empty?(x) do
          false -> :has_data
          true -> :empty
        end
      end
    end
    """
    |> to_source_file()
    |> run_check(NoCaseTrueFalse)
    |> assert_issue()
  end

  test "issue: case with true/wildcard clauses" do
    """
    defmodule Sample do
      def f(x) do
        case x > 0 do
          true -> :positive
          _ -> :other
        end
      end
    end
    """
    |> to_source_file()
    |> run_check(NoCaseTrueFalse)
    |> assert_issue()
  end

  test "issue: case with false/wildcard clauses" do
    """
    defmodule Sample do
      def f(x) do
        case x > 0 do
          false -> :other
          _ -> :positive
        end
      end
    end
    """
    |> to_source_file()
    |> run_check(NoCaseTrueFalse)
    |> assert_issue()
  end
end
