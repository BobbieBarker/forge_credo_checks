defmodule ForgeCredoChecks.InconsistentParamNamesTest do
  use Credo.Test.Case

  alias ForgeCredoChecks.InconsistentParamNames

  test "no issue: single-clause function" do
    """
    defmodule Sample do
      def f(prev, current, steps), do: {prev, current, steps}
    end
    """
    |> to_source_file()
    |> run_check(InconsistentParamNames)
    |> refute_issues()
  end

  test "no issue: matching param names across clauses" do
    """
    defmodule Sample do
      defp do_fib(prev, _current, 0), do: prev
      defp do_fib(prev, current, steps), do: do_fib(current, prev + current, steps - 1)
    end
    """
    |> to_source_file()
    |> run_check(InconsistentParamNames)
    |> refute_issues()
  end

  test "no issue: underscore-prefixed variants share the base name" do
    """
    defmodule Sample do
      def render(:html, data), do: data
      def render(_format, data), do: data
    end
    """
    |> to_source_file()
    |> run_check(InconsistentParamNames)
    |> refute_issues()
  end

  test "no issue: literal/destructuring patterns skip their position" do
    """
    defmodule Sample do
      def step({:ok, x}, acc), do: [x | acc]
      def step({:error, reason}, acc), do: acc ++ [reason]
    end
    """
    |> to_source_file()
    |> run_check(InconsistentParamNames)
    |> refute_issues()
  end

  test "issue: first arg drifts from `current` to `prev`" do
    """
    defmodule Sample do
      defp do_fib(current, next, 0), do: {current, next}
      defp do_fib(prev, next, steps), do: do_fib(next, prev + next, steps - 1)
    end
    """
    |> to_source_file()
    |> run_check(InconsistentParamNames)
    |> assert_issue()
  end

  test "issue: same function name with different arities does not cross-pollute" do
    """
    defmodule Sample do
      def f(a, b), do: {a, b}
      def f(a, b, c), do: {a, b, c}
    end
    """
    |> to_source_file()
    |> run_check(InconsistentParamNames)
    |> refute_issues()
  end

  test "issue: drift surfaces despite a `when` guard" do
    """
    defmodule Sample do
      def parse(input, _opts) when is_binary(input), do: input
      def parse(raw, opts), do: parse(to_string(raw), opts)
    end
    """
    |> to_source_file()
    |> run_check(InconsistentParamNames)
    |> assert_issue()
  end
end
