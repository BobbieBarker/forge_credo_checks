defmodule ForgeCredoChecks.NoInlineRegexTest do
  use Credo.Test.Case

  alias ForgeCredoChecks.NoInlineRegex

  test "issue: inline regex in a one-line public function" do
    """
    defmodule Sample do
      def valid?(value), do: value =~ ~r/^ok$/
    end
    """
    |> to_source_file()
    |> run_check(NoInlineRegex)
    |> assert_issue()
  end

  test "issue: inline regex in a block function" do
    """
    defmodule Sample do
      def valid?(value) do
        value =~ ~r/^ok$/
      end
    end
    """
    |> to_source_file()
    |> run_check(NoInlineRegex)
    |> assert_issue()
  end

  test "issue: inline regex passed to Regex.match?/2" do
    """
    defmodule Sample do
      def valid?(value) do
        Regex.match?(~r/^ok$/, value)
      end
    end
    """
    |> to_source_file()
    |> run_check(NoInlineRegex)
    |> assert_issue()
  end

  test "issue: inline raw regex sigil" do
    """
    defmodule Sample do
      def valid?(value), do: value =~ ~R/^ok$/
    end
    """
    |> to_source_file()
    |> run_check(NoInlineRegex)
    |> assert_issue()
  end

  test "issue: inline regex in a private function" do
    """
    defmodule Sample do
      defp valid?(value), do: value =~ ~r/^ok$/
    end
    """
    |> to_source_file()
    |> run_check(NoInlineRegex)
    |> assert_issue()
  end

  test "issue: inline regex in a public macro" do
    """
    defmodule Sample do
      defmacro valid?(value) do
        quote do
          unquote(value) =~ ~r/^ok$/
        end
      end
    end
    """
    |> to_source_file()
    |> run_check(NoInlineRegex)
    |> assert_issue()
  end

  test "issue: inline regex in a private macro" do
    """
    defmodule Sample do
      defmacrop valid?(value) do
        quote do
          unquote(value) =~ ~r/^ok$/
        end
      end
    end
    """
    |> to_source_file()
    |> run_check(NoInlineRegex)
    |> assert_issue()
  end

  test "issue: multiple inline regexes produce multiple issues" do
    """
    defmodule Sample do
      def valid?(value) do
        Regex.match?(~r/^ok$/, value) or Regex.match?(~R/^yes$/, value)
      end
    end
    """
    |> to_source_file()
    |> run_check(NoInlineRegex)
    |> assert_issues(2)
  end

  test "no issue: regex module attribute" do
    """
    defmodule Sample do
      @valid_value ~r/^ok$/

      def valid?(value), do: value =~ @valid_value
    end
    """
    |> to_source_file()
    |> run_check(NoInlineRegex)
    |> refute_issues()
  end

  test "no issue: regex module attribute with options" do
    """
    defmodule Sample do
      @valid_value ~r/^ok$/i

      def valid?(value), do: value =~ @valid_value
    end
    """
    |> to_source_file()
    |> run_check(NoInlineRegex)
    |> refute_issues()
  end

  test "no issue: unrelated sigils in function bodies" do
    """
    defmodule Sample do
      def values do
        {~s(ok), ~S(ok), ~w(one two), ~W(one two)}
      end
    end
    """
    |> to_source_file()
    |> run_check(NoInlineRegex)
    |> refute_issues()
  end
end
