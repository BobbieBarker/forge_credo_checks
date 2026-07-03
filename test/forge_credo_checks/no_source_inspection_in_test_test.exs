defmodule ForgeCredoChecks.NoSourceInspectionInTestTest do
  use Credo.Test.Case

  alias ForgeCredoChecks.NoSourceInspectionInTest

  test "issue: module attribute holding a lib source path" do
    """
    defmodule FooTest do
      @impl_source "lib/forge_symphony/foo.ex"
      def check, do: File.read!(@impl_source) =~ "bar"
    end
    """
    |> to_source_file("test/forge_symphony/foo_contract_test.exs")
    |> run_check(NoSourceInspectionInTest)
    |> assert_issue()
  end

  test "issue: File.read! of a literal lib source path" do
    """
    defmodule FooTest do
      def check, do: File.read!("lib/forge_symphony/foo.ex") =~ "bar"
    end
    """
    |> to_source_file("test/forge_symphony/foo_test.exs")
    |> run_check(NoSourceInspectionInTest)
    |> assert_issue()
  end

  test "issue: Code.string_to_quoted! of a lib source path" do
    """
    defmodule FooTest do
      def ast, do: Code.string_to_quoted!("lib/forge_symphony/foo.ex")
    end
    """
    |> to_source_file("test/forge_symphony/foo_test.exs")
    |> run_check(NoSourceInspectionInTest)
    |> assert_issue()
  end

  test "no issue: reading a generated or fixture file that is not lib/*.ex" do
    """
    defmodule FooTest do
      @fixture "test/fixtures/manifest.yml"
      def read_exclude, do: File.read!(Path.join(dir, ".git/info/exclude")) =~ "x"
      def read_lcov, do: File.read!("cover/lcov.info") =~ "SF:"
    end
    """
    |> to_source_file("test/forge_symphony/foo_test.exs")
    |> run_check(NoSourceInspectionInTest)
    |> refute_issues()
  end

  test "no issue: a lib source path outside a test file" do
    """
    defmodule Foo do
      @template "lib/forge_symphony/template.ex"
      def read, do: File.read!(@template)
    end
    """
    |> to_source_file("lib/forge_symphony/foo.ex")
    |> run_check(NoSourceInspectionInTest)
    |> refute_issues()
  end

  test "no issue: ordinary test module attributes and file reads" do
    """
    defmodule FooTest do
      @moduledoc "a test"
      @tag :integration
      @endpoint MyApp.Endpoint
      def read_output, do: File.read!("/tmp/output.txt") =~ "done"
    end
    """
    |> to_source_file("test/forge_symphony/foo_test.exs")
    |> run_check(NoSourceInspectionInTest)
    |> refute_issues()
  end
end
