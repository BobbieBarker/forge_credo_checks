defmodule ForgeCredoChecks.MultilineStringConcatTest do
  use Credo.Test.Case

  alias ForgeCredoChecks.MultilineStringConcat

  describe "no issue" do
    test "single-line concatenation of literals is not flagged" do
      """
      defmodule Sample do
        def banner, do: "a" <> "b" <> "c"
      end
      """
      |> to_source_file()
      |> run_check(MultilineStringConcat)
      |> refute_issues()
    end

    test "concatenating a variable operand is not flagged" do
      """
      defmodule Sample do
        def greeting(name) do
          "prefix " <>
            name
        end
      end
      """
      |> to_source_file()
      |> run_check(MultilineStringConcat)
      |> refute_issues()
    end

    test "a variable in the middle of a multi-line chain is not flagged" do
      """
      defmodule Sample do
        def greeting(name) do
          "hello " <>
            name <>
            "!"
        end
      end
      """
      |> to_source_file()
      |> run_check(MultilineStringConcat)
      |> refute_issues()
    end

    test "an interpolated operand is not a static literal and is not flagged" do
      """
      defmodule Sample do
        def render(x) do
          "a" <>
            "b\#{x}"
        end
      end
      """
      |> to_source_file()
      |> run_check(MultilineStringConcat)
      |> refute_issues()
    end

    test "a single string literal on multiple lines uses no concatenation" do
      ~S'''
      defmodule Sample do
        def banner do
          """
          the quick brown fox
          jumps over the lazy dog
          """
        end
      end
      '''
      |> to_source_file()
      |> run_check(MultilineStringConcat)
      |> refute_issues()
    end
  end

  describe "issue" do
    test "a multi-line three-operand literal chain yields exactly one issue" do
      """
      defmodule Sample do
        def banner do
          "the quick brown fox " <>
            "jumps over " <>
            "the lazy dog"
        end
      end
      """
      |> to_source_file()
      |> run_check(MultilineStringConcat)
      |> assert_heredoc_issue_at(3)
    end

    test "a multi-line two-operand literal chain yields exactly one issue" do
      """
      defmodule Sample do
        def banner do
          "the quick brown fox " <>
            "jumps over the lazy dog"
        end
      end
      """
      |> to_source_file()
      |> run_check(MultilineStringConcat)
      |> assert_heredoc_issue_at(3)
    end

    test "a multi-line literal chain assigned to a variable yields one issue" do
      """
      defmodule Sample do
        def banner do
          text =
            "the quick brown fox " <>
              "jumps over " <>
              "the lazy dog"

          text
        end
      end
      """
      |> to_source_file()
      |> run_check(MultilineStringConcat)
      |> assert_heredoc_issue_at(4)
    end

    test "two independent multi-line literal chains yield two issues" do
      """
      defmodule Sample do
        def first do
          "the quick brown fox " <>
            "jumps over the lazy dog"
        end

        def second do
          "sphinx of black quartz " <>
            "judge my vow"
        end
      end
      """
      |> to_source_file()
      |> run_check(MultilineStringConcat)
      |> assert_issues(2)
    end
  end

  defp assert_heredoc_issue_at(issues, line_no) do
    assert [issue] = issues
    assert issue.line_no == line_no
    assert issue.trigger == "<>"
    assert issue.message =~ "heredoc"
  end
end
