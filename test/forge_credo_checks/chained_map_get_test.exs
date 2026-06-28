defmodule ForgeCredoChecks.ChainedMapGetTest do
  use Credo.Test.Case

  alias ForgeCredoChecks.ChainedMapGet

  @message "Normalize the input shape at the boundary; do not fish across multiple sources."

  describe "no issue" do
    test "Map.get/3 default is not multi-source fishing" do
      """
      defmodule Sample do
        def issue(context), do: Map.get(context, :issue, :none)
      end
      """
      |> to_source_file()
      |> run_check(ChainedMapGet)
      |> refute_issues()
    end

    test "Map.get/2 with literal fallback belongs to the broader check only" do
      """
      defmodule Sample do
        def retries(opts), do: Map.get(opts, :retries) || 0
      end
      """
      |> to_source_file()
      |> run_check(ChainedMapGet)
      |> refute_issues()
    end

    test "right-hand Map.get/3 is not the chained Map.get/2 subset" do
      """
      defmodule Sample do
        def issue(issue, key) do
          Map.get(issue, key) ||
            Map.get(issue, Atom.to_string(key), "")
        end
      end
      """
      |> to_source_file()
      |> run_check(ChainedMapGet)
      |> refute_issues()
    end

    test "normalized boundary value is fine" do
      """
      defmodule Sample do
        def issue(%{issue: issue}), do: issue
      end
      """
      |> to_source_file()
      |> run_check(ChainedMapGet)
      |> refute_issues()
    end

    test "multi-clause boundary-normalized values are not flagged" do
      """
      defmodule Sample do
        def issue(%{issue: issue}), do: issue
        def issue(_missing), do: :none
      end
      """
      |> to_source_file()
      |> run_check(ChainedMapGet)
      |> refute_issues()
    end
  end

  describe "issue" do
    test "Map.get/2 on both sides of ||" do
      """
      defmodule Sample do
        def issue(context, arguments) do
          Map.get(context, :issue) || Map.get(arguments, :issue)
        end
      end
      """
      |> to_source_file()
      |> run_check(ChainedMapGet)
      |> assert_single_issue_at(3)
    end

    test "nested chained Map.get/2 inside another call" do
      """
      defmodule Sample do
        def issue(context, arguments) do
          normalize(Map.get(context, :issue) || Map.get(arguments, :issue))
        end
      end
      """
      |> to_source_file()
      |> run_check(ChainedMapGet)
      |> assert_single_issue_at(3)
    end

    test "piped two-argument Map.get on both sides of ||" do
      """
      defmodule Sample do
        def issue(context, arguments) do
          (context |> Map.get(:issue)) || (arguments |> Map.get(:issue))
        end
      end
      """
      |> to_source_file()
      |> run_check(ChainedMapGet)
      |> assert_single_issue_at(3)
    end

    test "multi-clause function with one chained Map.get/2 emits one issue" do
      """
      defmodule Sample do
        def issue(context, arguments), do: Map.get(context, :issue) || Map.get(arguments, :issue)
        def issue(_context, _arguments, default), do: default
      end
      """
      |> to_source_file()
      |> run_check(ChainedMapGet)
      |> assert_single_issue_at(2)
    end
  end

  defp assert_single_issue_at(issues, line_no) do
    assert [issue] = issues
    assert_issue([issue], %{line_no: line_no, message: @message, trigger: "||"})
  end
end
