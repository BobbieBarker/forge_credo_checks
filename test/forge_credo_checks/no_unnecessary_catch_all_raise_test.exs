defmodule ForgeCredoChecks.NoUnnecessaryCatchAllRaiseTest do
  use Credo.Test.Case

  alias ForgeCredoChecks.NoUnnecessaryCatchAllRaise

  test "no issue: clauses that return values" do
    """
    defmodule Sample do
      def parse(list) when is_list(list), do: {:ok, list}
      def parse(_), do: {:error, :invalid}
    end
    """
    |> to_source_file()
    |> run_check(NoUnnecessaryCatchAllRaise)
    |> refute_issues()
  end

  test "no issue: clause with logic before raise" do
    """
    defmodule Sample do
      def parse(_) do
        :telemetry.execute([:bad_call], %{})
        raise ArgumentError, "no"
      end
    end
    """
    |> to_source_file()
    |> run_check(NoUnnecessaryCatchAllRaise)
    |> refute_issues()
  end

  test "no issue: guarded catch-all is not flagged" do
    """
    defmodule Sample do
      def parse(x) when not is_list(x), do: raise(ArgumentError, "expected a list")
    end
    """
    |> to_source_file()
    |> run_check(NoUnnecessaryCatchAllRaise)
    |> refute_issues()
  end

  test "issue: catch-all that only raises" do
    """
    defmodule Sample do
      def parse(list) when is_list(list), do: {:ok, list}
      def parse(_), do: raise(ArgumentError, "expected a list")
    end
    """
    |> to_source_file()
    |> run_check(NoUnnecessaryCatchAllRaise)
    |> assert_issue()
  end

  test "issue: defp catch-all with multi-arg wildcards" do
    """
    defmodule Sample do
      defp dispatch(:ok, x), do: {:ok, x}
      defp dispatch(_, _), do: raise("unhandled")
    end
    """
    |> to_source_file()
    |> run_check(NoUnnecessaryCatchAllRaise)
    |> assert_issue()
  end

  test "issue: named-underscore wildcards still count" do
    """
    defmodule Sample do
      def render(:html, data), do: data
      def render(_format, _data), do: raise("unsupported")
    end
    """
    |> to_source_file()
    |> run_check(NoUnnecessaryCatchAllRaise)
    |> assert_issue()
  end
end
