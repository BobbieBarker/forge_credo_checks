defmodule ForgeCredoChecks.NamespaceTrespassingTest do
  use Credo.Test.Case

  alias ForgeCredoChecks.NamespaceTrespassing

  test "issue: module defined under Phoenix" do
    """
    defmodule Phoenix.Helpers do
      def hi, do: :ok
    end
    """
    |> to_source_file()
    |> run_check(NamespaceTrespassing)
    |> assert_issue()
  end

  test "issue: module defined under Ecto" do
    """
    defmodule Ecto.MyType do
      def cast(v), do: {:ok, v}
    end
    """
    |> to_source_file()
    |> run_check(NamespaceTrespassing)
    |> assert_issue()
  end

  test "no issue: own namespace nesting a dependency name" do
    """
    defmodule MyApp.Phoenix.Helpers do
      def hi, do: :ok
    end
    """
    |> to_source_file()
    |> run_check(NamespaceTrespassing)
    |> refute_issues()
  end

  test "no issue: ordinary application module" do
    """
    defmodule MyApp.Accounts do
      def list, do: []
    end
    """
    |> to_source_file()
    |> run_check(NamespaceTrespassing)
    |> refute_issues()
  end

  test "no issue: Mix.Tasks is the required home for custom mix tasks" do
    """
    defmodule Mix.Tasks.MyApp.Seed do
      use Mix.Task
      def run(_), do: :ok
    end
    """
    |> to_source_file()
    |> run_check(NamespaceTrespassing)
    |> refute_issues()
  end

  test "config: custom reserved namespaces" do
    """
    defmodule Acme.Widget do
      def go, do: :ok
    end
    """
    |> to_source_file()
    |> run_check(NamespaceTrespassing, namespaces: [:Acme])
    |> assert_issue()
  end
end
