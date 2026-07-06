defmodule ForgeCredoChecks.TaintedSourceInspectionTest do
  use Credo.Test.Case

  alias ForgeCredoChecks.TaintedSourceInspection

  test "issue: =~ against File.read! source text" do
    issue =
      """
      defmodule SourceGrepTest do
        def check do
          content = File.read!("lib/anubis/template_variables.ex")
          assert content =~ "def template_variables"
        end
      end
      """
      |> to_source_file("test/anubis/source_grep_test.exs")
      |> run_check(TaintedSourceInspection)
      |> assert_issue(%{trigger: "=~"})
      |> List.first()

    assert issue.message =~ "`=~`"
    assert issue.message =~ "contracts/template_variables_contract_test.exs"
    assert issue.message =~ ".md"
    assert issue.message =~ ".yaml"
    assert issue.message =~ ":excluded_paths"
  end

  test "issue: String.contains? through a source-path module attribute" do
    """
    defmodule SourceGrepTest do
      @source_path "lib/anubis/template_variables.exs"

      def check do
        content = File.read!(@source_path)
        String.contains?(content, "template_variables")
      end
    end
    """
    |> to_source_file("test/anubis/source_grep_test.exs")
    |> run_check(TaintedSourceInspection)
    |> assert_issue(%{trigger: "String.contains?"})
  end

  test "issue: Regex.* against text tainted from File.stream!" do
    """
    defmodule SourceGrepTest do
      def check do
        lines = File.stream!("lib/anubis/template_variables.ex")
        content = Enum.join(lines)
        Regex.match?(~r/template_variables/, content)
      end
    end
    """
    |> to_source_file("test/anubis/source_grep_test.exs")
    |> run_check(TaintedSourceInspection)
    |> assert_issue(%{trigger: "Regex.match?"})
  end

  test "issue: Code.eval_string against tainted source text" do
    """
    defmodule SourceGrepTest do
      def check do
        content = File.read!("lib/anubis/generated_rule.ex")
        Code.eval_string(content)
      end
    end
    """
    |> to_source_file("test/anubis/source_grep_test.exs")
    |> run_check(TaintedSourceInspection)
    |> assert_issue(%{trigger: "Code.eval_string"})
  end

  test "issue: callback grep over a tainted File.stream!" do
    """
    defmodule SourceGrepTest do
      def check do
        File.stream!("lib/anubis/generated_rule.ex")
        |> Enum.any?(&String.contains?(&1, "replace_state"))
      end
    end
    """
    |> to_source_file("test/anubis/source_grep_test.exs")
    |> run_check(TaintedSourceInspection)
    |> assert_issue(%{trigger: "String.contains?"})
  end

  test "issue: segmented Path.join source path with dynamic directory pieces" do
    """
    defmodule SourceGrepTest do
      @source_path Path.join([__DIR__, "..", "lib", "foo.ex"])

      def check do
        content = File.read!(@source_path)
        assert content =~ "def foo"
      end
    end
    """
    |> to_source_file("test/anubis/source_grep_test.exs")
    |> run_check(TaintedSourceInspection)
    |> assert_issue(%{trigger: "=~"})
  end

  test "no issue: terminal doc and artifact reads are outside the check" do
    """
    defmodule ArtifactScanTest do
      def check do
        markdown = File.read!("README.md")
        text = File.read!("priv/report.txt")
        yml = File.read!("config/template.yml")
        yaml = File.read!("config/template.yaml")
        doc_example = File.read!("docs/example.exs")

        markdown =~ "Usage"
        String.contains?(text, "ok")
        Regex.match?(~r/key/, yml)
        String.contains?(yaml, "value")
        Code.eval_string(doc_example)
      end
    end
    """
    |> to_source_file("test/anubis/artifact_scan_test.exs")
    |> run_check(TaintedSourceInspection)
    |> refute_issues()
  end

  test "no issue: reads under test/ are not source-grep violations" do
    """
    defmodule TestSourceScanTest do
      def check do
        content = File.read!("test/support/generated_rule_test.exs")
        assert content =~ "defmodule"
      end
    end
    """
    |> to_source_file("test/anubis/test_source_scan_test.exs")
    |> run_check(TaintedSourceInspection)
    |> refute_issues()
  end

  test "no issue: source paths as plain data do not taint without a source read" do
    """
    defmodule SourcePathDataTest do
      @source_path "lib/anubis/template_variables.ex"

      def check do
        assert @source_path =~ "template_variables"
      end
    end
    """
    |> to_source_file("test/anubis/source_path_data_test.exs")
    |> run_check(TaintedSourceInspection)
    |> refute_issues()
  end

  test "no issue: excluded_paths skips migration-bridge files" do
    """
    defmodule LegacySourceGrepTest do
      def check do
        content = File.read!("lib/anubis/template_variables.ex")
        assert content =~ "template_variables"
      end
    end
    """
    |> to_source_file("test/legacy_source_grep/source_grep_test.exs")
    |> run_check(TaintedSourceInspection, excluded_paths: [~r"^test/legacy_source_grep/"])
    |> refute_issues()
  end

  test "issue: not skipped when excluded_paths does not match" do
    """
    defmodule LegacySourceGrepTest do
      def check do
        content = File.read!("lib/anubis/template_variables.ex")
        assert content =~ "template_variables"
      end
    end
    """
    |> to_source_file("test/legacy_source_grep/source_grep_test.exs")
    |> run_check(TaintedSourceInspection, excluded_paths: [~r"^test/other/"])
    |> assert_issue(%{trigger: "=~"})
  end
end
