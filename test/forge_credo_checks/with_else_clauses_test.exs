defmodule ForgeCredoChecks.WithElseClausesTest do
  use Credo.Test.Case

  alias ForgeCredoChecks.WithElseClauses

  test "no issue: with no else block" do
    """
    defmodule Sample do
      def go(raw) do
        with :ok <- verify(),
             {:ok, opts} <- parse_options(raw) do
          {:ok, opts}
        end
      end
    end
    """
    |> to_source_file()
    |> run_check(WithElseClauses)
    |> refute_issues()
  end

  test "no issue: with else block at threshold (default max_clauses: 1)" do
    """
    defmodule Sample do
      def go(raw) do
        with {:ok, opts} <- parse_options(raw) do
          {:ok, opts}
        else
          err -> err
        end
      end
    end
    """
    |> to_source_file()
    |> run_check(WithElseClauses)
    |> refute_issues()
  end

  test "issue: else block exceeding default threshold" do
    """
    defmodule Sample do
      def go(raw) do
        with :ok <- verify(),
             {:ok, opts} <- parse_options(raw) do
          {:ok, opts}
        else
          {:error, :missing} -> :missing
          {:error, :invalid} -> :invalid
          err -> err
        end
      end
    end
    """
    |> to_source_file()
    |> run_check(WithElseClauses)
    |> assert_issue()
  end

  test "configurable: max_clauses: 0 forbids else entirely" do
    """
    defmodule Sample do
      def go(raw) do
        with {:ok, opts} <- parse_options(raw) do
          {:ok, opts}
        else
          err -> err
        end
      end
    end
    """
    |> to_source_file()
    |> run_check(WithElseClauses, max_clauses: 0)
    |> assert_issue()
  end

  test "configurable: max_clauses: 3 allows up to three else clauses" do
    """
    defmodule Sample do
      def go(raw) do
        with :ok <- verify(),
             {:ok, opts} <- parse_options(raw) do
          {:ok, opts}
        else
          {:error, :missing} -> :missing
          {:error, :invalid} -> :invalid
          err -> err
        end
      end
    end
    """
    |> to_source_file()
    |> run_check(WithElseClauses, max_clauses: 3)
    |> refute_issues()
  end
end
