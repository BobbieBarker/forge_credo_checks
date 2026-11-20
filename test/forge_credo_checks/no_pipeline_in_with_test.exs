defmodule ForgeCredoChecks.NoPipelineInWithTest do
  use Credo.Test.Case, async: true

  alias ForgeCredoChecks.NoPipelineInWith

  for clause <- [
        "{:ok, value} <- input |> normalize() |> validate()",
        "{:ok, value} <- (input |> normalize())",
        "value = input |> normalize()",
        "input |> validate()"
      ] do
    test "flags direct pipeline in #{clause}" do
      """
      with #{unquote(clause)} do
        :ok
      end
      """
      |> to_source_file()
      |> run_check(NoPipelineInWith)
      |> assert_issue(fn issue ->
        assert issue.trigger == "|>"
        assert issue.line_no == 1
      end)
    end
  end

  test "reports each offending clause once, even with multiple pipe operators" do
    """
    with {:ok, first} <- input |> normalize() |> validate(),
         {:ok, second} <- first |> transform() |> validate() do
      second
    end
    """
    |> to_source_file()
    |> run_check(NoPipelineInWith)
    |> assert_issues(fn issues -> assert length(issues) == 2 end)
  end

  test "allows pipelines outside the clause chain, including do and else bodies" do
    """
    input = raw |> normalize() |> prepare()
    with {:ok, value} <- validate(input) do
      value |> transform() |> finish()
    else
      error -> error |> normalize_error() |> report()
    end
    """
    |> to_source_file()
    |> run_check(NoPipelineInWith)
    |> refute_issues()
  end

  test "allows plain calls and pipeline literals" do
    """
    with {:ok, value} <- validate("|>"),
         :ok <- save(value) do
      value
    end
    """
    |> to_source_file()
    |> run_check(NoPipelineInWith)
    |> refute_issues()
  end

  test "checks nested with independently without duplicate reports" do
    """
    with {:ok, value} <- (with {:ok, inner} <- raw |> normalize() do
                           {:ok, inner}
                         end) do
      with :ok <- value |> save() do
        :ok
      end
    end
    """
    |> to_source_file()
    |> run_check(NoPipelineInWith)
    |> assert_issues(fn issues -> assert length(issues) == 2 end)
  end

  test "flags pipelines in anonymous function bodies passed to a clause call" do
    """
    with {:ok, value} <- apply_callback(fn input -> input |> normalize() end) do
      value
    end
    """
    |> to_source_file()
    |> run_check(NoPipelineInWith)
    |> assert_issue()
  end

  test "ignores ordinary calls named with without a do block" do
    """
    with()
    with(input |> normalize())
    """
    |> to_source_file()
    |> run_check(NoPipelineInWith)
    |> refute_issues()
  end

  test "reports the pipeline location in a multiline clause" do
    """
    with {:ok, value} <-
           input
           |> normalize()
           |> validate() do
      value
    end
    """
    |> to_source_file()
    |> run_check(NoPipelineInWith)
    |> assert_issue(fn issue ->
      assert issue.line_no == 4
      assert issue.trigger == "|>"
    end)
  end

  for clause <- [
        "{:ok, value} <- validate(raw |> normalize())",
        "{:ok, value} <- {:ok, raw |> normalize()}",
        "{:ok, value} <- validate(%{input: raw |> normalize()})",
        "{:ok, value} <- validate([raw |> normalize()])",
        "{:ok, value} <- validate(option: raw |> normalize())",
        "{:ok, value} <- validate({:input, :raw, raw |> normalize()})",
        "{:ok, value} <- validate(&(normalize(&1) |> finish()))",
        "{:ok, value} <- (if ready?, do: raw |> normalize(), else: :error)",
        "value = validate(raw |> normalize())",
        "validate(raw |> normalize())"
      ] do
    test "flags nested pipeline in #{clause}" do
      """
      with #{unquote(clause)} do
        :ok
      end
      """
      |> to_source_file()
      |> run_check(NoPipelineInWith)
      |> assert_issue(fn issue ->
        assert issue.trigger == "|>"
        assert issue.line_no == 1
        assert issue.message =~ "Extract"
        assert issue.message =~ "evaluation order"
        assert issue.message =~ "Do not hide"
        assert issue.message =~ "{:ok, ...}"
      end)
    end
  end

  test "reports a clause once when separate arguments contain pipelines" do
    """
    with :ok <- validate(raw |> normalize(), other |> prepare()) do
      :ok
    end
    """
    |> to_source_file()
    |> run_check(NoPipelineInWith)
    |> assert_issue()
  end

  test "nested with bodies remain outside their own clause chains" do
    """
    with {:ok, value} <- (with {:ok, inner} <- parse(raw) do
                           inner |> normalize() |> validate()
                         else
                           error -> error |> report()
                         end) do
      value
    end
    """
    |> to_source_file()
    |> run_check(NoPipelineInWith)
    |> refute_issues()
  end
end
