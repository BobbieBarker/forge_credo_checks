defmodule ForgeCredoChecks.MultilineStringConcatTest do
  use Credo.Test.Case

  alias ForgeCredoChecks.MultilineStringConcat

  @message "Replace multi-line string-literal `<>` concatenation with a heredoc."

  describe "issue" do
    test "three-operand multi-line chain of pure literals yields one issue" do
      """
      defmodule Sample do
        def go do
          "a" <>
          "b" <>
          "c"
        end
      end
      """
      |> to_source_file()
      |> run_check(MultilineStringConcat)
      |> assert_single_issue_at(3)
    end

    test "two-operand multi-line chain of pure literals yields one issue" do
      """
      defmodule Sample do
        def go do
          "a" <>
          "b"
        end
      end
      """
      |> to_source_file()
      |> run_check(MultilineStringConcat)
      |> assert_single_issue_at(3)
    end

    test "issue message suggests a heredoc" do
      """
      defmodule Sample do
        def go do
          "a" <>
          "b"
        end
      end
      """
      |> to_source_file()
      |> run_check(MultilineStringConcat)
      |> assert_issue(fn issue ->
        assert issue.message == @message
        assert issue.trigger == "<>"
      end)
    end

    test "chain nested inside a call is flagged once" do
      """
      defmodule Sample do
        def go do
          IO.puts("a" <>
          "b" <>
          "c")
        end
      end
      """
      |> to_source_file()
      |> run_check(MultilineStringConcat)
      |> assert_single_issue_at(3)
    end
  end

  describe "no issue" do
    test "single-line three-operand chain of literals is not flagged" do
      """
      defmodule Sample do
        def go, do: "a" <> "b" <> "c"
      end
      """
      |> to_source_file()
      |> run_check(MultilineStringConcat)
      |> refute_issues()
    end

    test "single-line two-operand chain of literals is not flagged" do
      """
      defmodule Sample do
        def go, do: "a" <> "b"
      end
      """
      |> to_source_file()
      |> run_check(MultilineStringConcat)
      |> refute_issues()
    end

    test "prefix literal concatenated with a variable is not flagged" do
      """
      defmodule Sample do
        def go(some_var), do: "prefix " <> some_var
      end
      """
      |> to_source_file()
      |> run_check(MultilineStringConcat)
      |> refute_issues()
    end

    test "variable concatenated with a literal is not flagged" do
      """
      defmodule Sample do
        def go(some_var) do
          some_var <>
          "suffix"
        end
      end
      """
      |> to_source_file()
      |> run_check(MultilineStringConcat)
      |> refute_issues()
    end

    test "chain with an interpolated operand is not flagged" do
      ~S"""
      defmodule Sample do
        def go(x) do
          "a" <>
          "b#{x}"
        end
      end
      """
      |> to_source_file()
      |> run_check(MultilineStringConcat)
      |> refute_issues()
    end

    test "heredoc is not flagged" do
      """
      defmodule Sample do
        def go do
          \"\"\"
          foo
          bar
          \"\"\"
        end
      end
      """
      |> to_source_file()
      |> run_check(MultilineStringConcat)
      |> refute_issues()
    end

    test "multi-line chain mixing a literal and a function call is not flagged" do
      """
      defmodule Sample do
        def go do
          "a" <>
          build_suffix()
        end
      end
      """
      |> to_source_file()
      |> run_check(MultilineStringConcat)
      |> refute_issues()
    end

    test "plain string literal is not flagged" do
      """
      defmodule Sample do
        def go, do: "just a string"
      end
      """
      |> to_source_file()
      |> run_check(MultilineStringConcat)
      |> refute_issues()
    end
  end

  defp assert_single_issue_at(issues, line_no) do
    assert [issue] = issues
    assert_issue([issue], %{line_no: line_no, message: @message, trigger: "<>"})
  end
end
