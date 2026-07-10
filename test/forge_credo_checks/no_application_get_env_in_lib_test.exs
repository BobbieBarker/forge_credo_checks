defmodule ForgeCredoChecks.NoApplicationGetEnvInLibTest do
  use Credo.Test.Case

  alias ForgeCredoChecks.NoApplicationGetEnvInLib

  test "issue: Application.get_env/2 in a lib/*.ex file yields exactly one issue" do
    """
    defmodule Sample do
      def config, do: Application.get_env(:app, :key)
    end
    """
    |> to_source_file("lib/sample.ex")
    |> run_check(NoApplicationGetEnvInLib)
    |> assert_issue(%{line_no: 2, trigger: "Application.get_env"})
  end

  test "issue: Application.get_env/3 (with default) in a lib/*.ex file" do
    """
    defmodule Sample do
      def config, do: Application.get_env(:app, :key, :default)
    end
    """
    |> to_source_file("lib/sample.ex")
    |> run_check(NoApplicationGetEnvInLib)
    |> assert_issue(%{trigger: "Application.get_env"})
  end

  test "issue: multiple get_env calls produce multiple issues" do
    """
    defmodule Sample do
      def a, do: Application.get_env(:app, :a)
      def b, do: Application.get_env(:app, :b)
    end
    """
    |> to_source_file("lib/sample.ex")
    |> run_check(NoApplicationGetEnvInLib)
    |> assert_issues(2)
  end

  test "no issue: Application.compile_env in a lib/*.ex file with NO allowlist param set" do
    """
    defmodule Sample do
      def config, do: Application.compile_env(:app, :key)
    end
    """
    |> to_source_file("lib/sample.ex")
    |> run_check(NoApplicationGetEnvInLib)
    |> refute_issues()
  end

  test "no issue: Application.compile_env/3 (with default) in a lib/*.ex file" do
    """
    defmodule Sample do
      def config, do: Application.compile_env(:app, :key, :default)
    end
    """
    |> to_source_file("lib/sample.ex")
    |> run_check(NoApplicationGetEnvInLib)
    |> refute_issues()
  end

  test "no issue: Application.fetch_env / fetch_env! in a lib/*.ex file (explicitly out of scope)" do
    """
    defmodule Sample do
      def a, do: Application.fetch_env(:app, :key)
      def b, do: Application.fetch_env!(:app, :key)
    end
    """
    |> to_source_file("lib/sample.ex")
    |> run_check(NoApplicationGetEnvInLib)
    |> refute_issues()
  end

  test "no issue: a lib/*.ex file whose path matches allowed_paths yields no issue" do
    """
    defmodule Sample do
      def config, do: Application.get_env(:app, :key)
    end
    """
    |> to_source_file("lib/forge/ports/config_reader.ex")
    |> run_check(NoApplicationGetEnvInLib, allowed_paths: [~r"^lib/forge/ports/"])
    |> refute_issues()
  end

  test "issue: allowed_paths override that does NOT match still flags the file" do
    """
    defmodule Sample do
      def config, do: Application.get_env(:app, :key)
    end
    """
    |> to_source_file("lib/forge/core/runner.ex")
    |> run_check(NoApplicationGetEnvInLib, allowed_paths: [~r"^lib/forge/ports/"])
    |> assert_issue()
  end

  test "allowed_paths override flips a previously-flagged file to no-issue" do
    source = """
    defmodule Sample do
      def config, do: Application.get_env(:app, :key)
    end
    """

    # Default (no allowlist): flagged.
    source
    |> to_source_file("lib/forge/runtime/config.ex")
    |> run_check(NoApplicationGetEnvInLib)
    |> assert_issue()

    # Same file, now allowed: no issue.
    source
    |> to_source_file("lib/forge/runtime/config.ex")
    |> run_check(NoApplicationGetEnvInLib, allowed_paths: [~r"^lib/forge/runtime/"])
    |> refute_issues()
  end

  test "no issue: Application.get_env in a non-lib file (test/foo_test.exs)" do
    """
    defmodule SampleTest do
      def config, do: Application.get_env(:app, :key)
    end
    """
    |> to_source_file("test/foo_test.exs")
    |> run_check(NoApplicationGetEnvInLib)
    |> refute_issues()
  end

  test "no issue: Application.get_env in a config/ file is out of scope" do
    """
    defmodule Sample do
      def config, do: Application.get_env(:app, :key)
    end
    """
    |> to_source_file("config/config.exs")
    |> run_check(NoApplicationGetEnvInLib)
    |> refute_issues()
  end

  test "included_paths override narrows scope: a non-lib file matching included_paths is checked" do
    """
    defmodule SampleTest do
      def config, do: Application.get_env(:app, :key)
    end
    """
    |> to_source_file("test/foo_test.exs")
    |> run_check(NoApplicationGetEnvInLib, included_paths: [~r"^test/"])
    |> assert_issue()
  end

  test "issue message names Application.get_env and suggests compile_env" do
    issue =
      """
      defmodule Sample do
        def config, do: Application.get_env(:app, :key)
      end
      """
      |> to_source_file("lib/sample.ex")
      |> run_check(NoApplicationGetEnvInLib)
      |> assert_issue()
      |> List.first()

    assert issue.message =~ "Application.get_env"
    assert issue.message =~ "compile_env"
  end
end
