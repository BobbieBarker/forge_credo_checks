defmodule ForgeCredoChecks.NoAnyOrTermTypesTest do
  use Credo.Test.Case

  alias ForgeCredoChecks.NoAnyOrTermTypes

  test "issue: any in a spec argument" do
    """
    defmodule Sample do
      @spec publish(any()) :: :ok
      def publish(_payload), do: :ok
    end
    """
    |> to_source_file()
    |> run_check(NoAnyOrTermTypes)
    |> assert_issue(fn issue ->
      assert issue.trigger == "any()"
    end)
  end

  test "issue: term in a spec return" do
    """
    defmodule Sample do
      @spec decode(binary()) :: term()
      def decode(payload), do: payload
    end
    """
    |> to_source_file()
    |> run_check(NoAnyOrTermTypes)
    |> assert_issue(fn issue ->
      assert issue.trigger == "term()"
    end)
  end

  test "issue: any and term inside nested spec types" do
    """
    defmodule Sample do
      @spec run((term() -> any())) :: {:ok, [term()]}
      def run(callback), do: {:ok, [callback.(:value)]}
    end
    """
    |> to_source_file()
    |> run_check(NoAnyOrTermTypes)
    |> assert_issues(fn issues ->
      assert Enum.map(issues, & &1.trigger) == ["term()", "any()", "term()"]
    end)
  end

  test "issue: distinct columns for each banned type on a shared spec line" do
    """
    defmodule Sample do
      @spec run((term() -> any())) :: {:ok, [term()]}
      def run(callback), do: {:ok, [callback.(:value)]}
    end
    """
    |> to_source_file()
    |> run_check(NoAnyOrTermTypes)
    |> assert_issues(fn issues ->
      assert Enum.map(issues, &{&1.trigger, &1.line_no, &1.column}) == [
               {"term()", 2, 14},
               {"any()", 2, 24},
               {"term()", 2, 42}
             ]
    end)
  end

  test "issue: repeated term on one type line gets distinct columns" do
    """
    defmodule Sample do
      @type pair :: {term(), term()}
    end
    """
    |> to_source_file()
    |> run_check(NoAnyOrTermTypes)
    |> assert_issues(fn issues ->
      assert Enum.map(issues, &{&1.trigger, &1.line_no, &1.column}) == [
               {"term()", 2, 18},
               {"term()", 2, 26}
             ]

      [first, second] = issues
      assert first.column != second.column
    end)
  end

  test "issue: any in a public type definition" do
    """
    defmodule Sample do
      @type payload :: %{optional(atom()) => any()}
    end
    """
    |> to_source_file()
    |> run_check(NoAnyOrTermTypes)
    |> assert_issue(fn issue ->
      assert issue.trigger == "any()"
    end)
  end

  test "issue: term in private and opaque type definitions" do
    """
    defmodule Sample do
      @typep raw_payload :: term()
      @opaque token :: {:token, term()}
    end
    """
    |> to_source_file()
    |> run_check(NoAnyOrTermTypes)
    |> assert_issues(fn issues ->
      assert Enum.map(issues, & &1.trigger) == ["term()", "term()"]
    end)
  end

  test "issue: callback and macrocallback broad types" do
    """
    defmodule Sample do
      @callback normalize(term()) :: any()
      @macrocallback build(any()) :: term()
    end
    """
    |> to_source_file()
    |> run_check(NoAnyOrTermTypes)
    |> assert_issues(fn issues ->
      assert Enum.map(issues, & &1.trigger) == ["term()", "any()", "any()", "term()"]
    end)
  end

  test "issue: term in spec constraints" do
    """
    defmodule Sample do
      @spec identity(value) :: value when value: term()
      def identity(value), do: value
    end
    """
    |> to_source_file()
    |> run_check(NoAnyOrTermTypes)
    |> assert_issue(fn issue ->
      assert issue.trigger == "term()"
    end)
  end

  test "no issue: specific specs and generic type variables" do
    """
    defmodule Sample do
      @type id :: pos_integer()
      @type result(value, reason) :: {:ok, value} | {:error, reason}
      @spec fetch(id()) :: result(String.t(), :not_found)
      def fetch(_id), do: {:error, :not_found}
    end
    """
    |> to_source_file()
    |> run_check(NoAnyOrTermTypes)
    |> refute_issues()
  end

  test "no issue: functions named any or term" do
    """
    defmodule Sample do
      @spec any(integer()) :: boolean()
      def any(value), do: value > 0

      @spec term(String.t()) :: :ok
      def term(_value), do: :ok
    end
    """
    |> to_source_file()
    |> run_check(NoAnyOrTermTypes)
    |> refute_issues()
  end

  test "no issue: remote types named any or term" do
    """
    defmodule Sample do
      @spec convert(MyTypes.term()) :: MyTypes.any()
      def convert(value), do: value
    end
    """
    |> to_source_file()
    |> run_check(NoAnyOrTermTypes)
    |> refute_issues()
  end

  test "no issue: bare type variables named any or term" do
    """
    defmodule Sample do
      @spec identity(term) :: term
      def identity(value), do: value

      @type box(any) :: {:ok, any}
    end
    """
    |> to_source_file()
    |> run_check(NoAnyOrTermTypes)
    |> refute_issues()
  end
end
