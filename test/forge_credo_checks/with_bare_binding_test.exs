defmodule ForgeCredoChecks.WithBareBindingTest do
  use Credo.Test.Case

  alias ForgeCredoChecks.WithBareBinding

  test "no issue: with chain using only <-" do
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
    |> run_check(WithBareBinding)
    |> refute_issues()
  end

  test "no issue: plain = inside the do block" do
    """
    defmodule Sample do
      def go(raw) do
        with {:ok, opts} <- parse_options(raw) do
          normalized = normalize(opts)
          {:ok, normalized}
        end
      end
    end
    """
    |> to_source_file()
    |> run_check(WithBareBinding)
    |> refute_issues()
  end

  test "no issue: plain = outside any with" do
    """
    defmodule Sample do
      def go(raw) do
        argv = normalize_argv(raw)
        {:ok, argv}
      end
    end
    """
    |> to_source_file()
    |> run_check(WithBareBinding)
    |> refute_issues()
  end

  test "issue: smuggled = binding between <- clauses" do
    """
    defmodule Sample do
      def go(raw) do
        with :ok <- verify(),
             argv = normalize_argv(raw),
             {:ok, opts} <- parse_options(argv) do
          {:ok, opts}
        end
      end
    end
    """
    |> to_source_file()
    |> run_check(WithBareBinding)
    |> assert_issue()
  end

  test "issue: = as the leading clause" do
    """
    defmodule Sample do
      def go(raw) do
        with argv = normalize_argv(raw),
             {:ok, opts} <- parse_options(argv) do
          {:ok, opts}
        end
      end
    end
    """
    |> to_source_file()
    |> run_check(WithBareBinding)
    |> assert_issue()
  end

  test "issue: multiple = clauses produce multiple issues" do
    """
    defmodule Sample do
      def go(raw) do
        with :ok <- verify(),
             argv = normalize_argv(raw),
             config = build_config(argv),
             {:ok, opts} <- parse_options(config) do
          {:ok, opts}
        end
      end
    end
    """
    |> to_source_file()
    |> run_check(WithBareBinding)
    |> assert_issues(fn issues -> assert length(issues) == 2 end)
  end

  test "issue: with that has an else block still flags = clauses" do
    """
    defmodule Sample do
      def go(raw) do
        with :ok <- verify(),
             argv = normalize_argv(raw),
             {:ok, opts} <- parse_options(argv) do
          {:ok, opts}
        else
          {:error, _} = err -> err
        end
      end
    end
    """
    |> to_source_file()
    |> run_check(WithBareBinding)
    |> assert_issue()
  end
end
