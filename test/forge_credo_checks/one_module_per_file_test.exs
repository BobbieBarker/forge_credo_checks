defmodule ForgeCredoChecks.OneModulePerFileTest do
  use Credo.Test.Case

  alias ForgeCredoChecks.OneModulePerFile

  test "no issue: a file with one module" do
    """
    defmodule First do
      def value, do: :ok
    end
    """
    |> to_source_file("lib/first.ex")
    |> run_check(OneModulePerFile)
    |> refute_issues()
  end

  test "no issue: a file with no modules" do
    """
    import Config

    config :sample, enabled: true
    """
    |> to_source_file("config/runtime.exs")
    |> run_check(OneModulePerFile)
    |> refute_issues()
  end

  test "issue: the second top-level module is flagged" do
    """
    defmodule First do
    end

    defmodule Second do
    end
    """
    |> to_source_file("lib/multiple.ex")
    |> run_check(OneModulePerFile)
    |> assert_issue(%{line_no: 4, trigger: "Second"})
  end

  test "issue: every module after the first is flagged" do
    """
    defmodule First do
    end

    defmodule Second do
    end

    defmodule Third do
    end
    """
    |> to_source_file("lib/multiple.ex")
    |> run_check(OneModulePerFile)
    |> assert_issues(fn issues ->
      assert Enum.map(issues, &{&1.line_no, &1.trigger}) == [{4, "Second"}, {7, "Third"}]
    end)
  end

  test "issue: a nested module is a second module definition" do
    """
    defmodule Outer do
      defmodule Inner do
      end
    end
    """
    |> to_source_file("lib/outer.ex")
    |> run_check(OneModulePerFile)
    |> assert_issue(%{line_no: 2, trigger: "Inner"})
  end

  test "issue: reopening the first module is another module definition" do
    """
    defmodule Sample do
      def first, do: :first
    end

    defmodule Sample do
      def second, do: :second
    end
    """
    |> to_source_file("lib/sample.ex")
    |> run_check(OneModulePerFile)
    |> assert_issue(%{line_no: 5, trigger: "Sample"})
  end

  test "no issue: module declarations inside quote are generated AST" do
    """
    defmodule Builder do
      defmacro build do
        quote do
          defmodule Generated.One do
          end

          defmodule Generated.Two do
          end
        end
      end
    end
    """
    |> to_source_file("lib/builder.ex")
    |> run_check(OneModulePerFile)
    |> refute_issues()
  end

  test "no issue: *_test.exs files are excluded by default" do
    """
    defmodule SampleTest do
      defmodule Fixture do
      end
    end
    """
    |> to_source_file("spec/sample_test.exs")
    |> run_check(OneModulePerFile)
    |> refute_issues()
  end

  test "no issue: files in a test directory are excluded by default" do
    source = """
    defmodule TestSupport do
      defmodule Fixture do
      end
    end
    """

    for filename <- [
          "apps/sample/test/support/fixture.ex",
          "apps\\sample\\test\\support\\fixture.ex"
        ] do
      source
      |> to_source_file(filename)
      |> run_check(OneModulePerFile)
      |> refute_issues()
    end
  end

  test "issue: excluded_paths can be emptied to enforce the rule in tests" do
    """
    defmodule SampleTest do
      defmodule Fixture do
      end
    end
    """
    |> to_source_file("test/sample_test.exs")
    |> run_check(OneModulePerFile, excluded_paths: [])
    |> assert_issue(%{line_no: 2, trigger: "Fixture"})
  end

  test "no issue: a custom excluded path skips the file" do
    """
    defmodule Generated.One do
    end

    defmodule Generated.Two do
    end
    """
    |> to_source_file("lib/generated/modules.ex")
    |> run_check(OneModulePerFile, excluded_paths: ["lib/generated/"])
    |> refute_issues()
  end

  test "issue: a non-matching custom exclusion does not skip the file" do
    """
    defmodule First do
    end

    defmodule Second do
    end
    """
    |> to_source_file("lib/multiple.ex")
    |> run_check(OneModulePerFile, excluded_paths: [~r"^lib/generated/"])
    |> assert_issue()
  end
end
