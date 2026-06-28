defmodule ForgeCredoChecks.MapGetWithOrTest do
  use Credo.Test.Case

  alias ForgeCredoChecks.MapGetWithOr

  @message "Use Map.get/3 for defaults, or normalize the data at its ingestion boundary."

  describe "no issue" do
    test "Map.get/3 default is the idiomatic local default" do
      """
      defmodule Sample do
        def retries(opts), do: Map.get(opts, :retries, 0)
      end
      """
      |> to_source_file()
      |> run_check(MapGetWithOr)
      |> refute_issues()
    end

    test "normalized boundary value is fine" do
      """
      defmodule Sample do
        def issue(%{issue: issue}), do: issue
      end
      """
      |> to_source_file()
      |> run_check(MapGetWithOr)
      |> refute_issues()
    end

    test "right side Map.get/2 is not flagged without a left Map.get/2" do
      """
      defmodule Sample do
        def issue(context, arguments) do
          context.issue || Map.get(arguments, :issue)
        end
      end
      """
      |> to_source_file()
      |> run_check(MapGetWithOr)
      |> refute_issues()
    end

    test "piped Map.get/3 default is not flagged" do
      """
      defmodule Sample do
        def retries(opts), do: opts |> Map.get(:retries, 0)
      end
      """
      |> to_source_file()
      |> run_check(MapGetWithOr)
      |> refute_issues()
    end

    test "other boolean operators are not flagged" do
      """
      defmodule Sample do
        def enabled?(opts), do: Map.get(opts, :enabled?) && true
      end
      """
      |> to_source_file()
      |> run_check(MapGetWithOr)
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
      |> run_check(MapGetWithOr)
      |> refute_issues()
    end
  end

  describe "issue" do
    test "nil-coalescing default with Map.get/2" do
      """
      defmodule Sample do
        def retries(opts) do
          Map.get(opts, :retries) || 0
        end
      end
      """
      |> to_source_file()
      |> run_check(MapGetWithOr)
      |> assert_single_issue_at(3)
    end

    test "multi-source fishing with Map.get/2 on both sides" do
      """
      defmodule Sample do
        def issue(context, arguments) do
          Map.get(context, :issue) || Map.get(arguments, :issue)
        end
      end
      """
      |> to_source_file()
      |> run_check(MapGetWithOr)
      |> assert_single_issue_at(3)
    end

    test "atom/string indifference with Map.get/2 followed by Map.get/3" do
      """
      defmodule Sample do
        def issue(issue, key) do
          Map.get(issue, key) ||
            Map.get(issue, Atom.to_string(key), "")
        end
      end
      """
      |> to_source_file()
      |> run_check(MapGetWithOr)
      |> assert_single_issue_at(3)
    end

    test "nested Map.get/2 with || inside another call" do
      """
      defmodule Sample do
        def retries(opts) do
          normalize(Map.get(opts, :retries) || 0)
        end
      end
      """
      |> to_source_file()
      |> run_check(MapGetWithOr)
      |> assert_single_issue_at(3)
    end

    test "piped two-argument Map.get followed by ||" do
      """
      defmodule Sample do
        def retries(opts) do
          (opts |> Map.get(:retries)) || 0
        end
      end
      """
      |> to_source_file()
      |> run_check(MapGetWithOr)
      |> assert_single_issue_at(3)
    end

    test "multi-clause function with one Map.get/2 || fallback emits one issue" do
      """
      defmodule Sample do
        def retries(%{opts: opts}), do: Map.get(opts, :retries) || 0
        def retries(_missing), do: 0
      end
      """
      |> to_source_file()
      |> run_check(MapGetWithOr)
      |> assert_single_issue_at(2)
    end
  end

  defp assert_single_issue_at(issues, line_no) do
    assert [issue] = issues
    assert_issue([issue], %{line_no: line_no, message: @message, trigger: "||"})
  end
end
