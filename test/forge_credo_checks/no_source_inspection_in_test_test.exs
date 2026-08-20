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

  test "issue guidance reshapes the public API instead of exporting a private helper" do
    """
    defmodule FooTest do
      def check, do: File.read!("lib/forge_symphony/foo.ex") =~ "bar"
    end
    """
    |> to_source_file("test/forge_symphony/foo_test.exs")
    |> run_check(NoSourceInspectionInTest)
    |> assert_issue(fn issue ->
      assert issue.message =~ "Reshape the public API"
      assert issue.message =~ "split the function or expose the concept"
      refute issue.message =~ "make it public"
      refute issue.message =~ "@doc false"
    end)
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

  test "no issue: source paths carried as plain data without reading them" do
    """
    defmodule DispatchContractTest do
      @decision %{specialist_file_path: "lib/forge_symphony/router.ex"}
      @off_dag_registry [
        %{id: :reviewer, file: "lib/forge_symphony/forge_reactor/steps/producer.ex"},
        %{id: :resolver, file: "lib/forge_symphony/forge_reactor/protocols/resolve.ex"}
      ]
      def ids, do: {@decision.specialist_file_path, Enum.map(@off_dag_registry, & &1.id)}
    end
    """
    |> to_source_file("test/forge_symphony/dispatch_contract_test.exs")
    |> run_check(NoSourceInspectionInTest)
    |> refute_issues()
  end

  test "issue: source paths carried as data then read and parsed dynamically" do
    """
    defmodule DispatchContractTest do
      @registry [%{file: "lib/forge_symphony/foo.ex"}]
      defp source_ast(rel), do: rel |> File.read!() |> Code.string_to_quoted!()
      def check, do: Enum.map(@registry, &source_ast(&1.file))
    end
    """
    |> to_source_file("test/forge_symphony/dispatch_contract_test.exs")
    |> run_check(NoSourceInspectionInTest)
    |> assert_issue()
  end

  test "no issue: a meta-lint that parses only test source names no lib path" do
    """
    defmodule AsyncGuardTest do
      defp test_files, do: Path.wildcard("test/**/*_test.exs")
      defp ast(path), do: path |> File.read!() |> Code.string_to_quoted!(file: path)
      def check, do: Enum.map(test_files(), &ast/1)
    end
    """
    |> to_source_file("test/forge_symphony/async_guard_test.exs")
    |> run_check(NoSourceInspectionInTest)
    |> refute_issues()
  end

  test "no issue: an architectural glob-scan of lib carries no literal source path" do
    """
    defmodule ObsidianFreeTest do
      @lib_dir Path.join(File.cwd!(), "lib")
      defp files, do: Path.wildcard(Path.join(@lib_dir, "**/*.ex"))

      def check do
        for path <- files(),
            content = File.read!(path),
            String.contains?(content, "obsidian"),
            do: path
      end
    end
    """
    |> to_source_file("test/forge_symphony/obsidian_free_test.exs")
    |> run_check(NoSourceInspectionInTest)
    |> refute_issues()
  end
end
