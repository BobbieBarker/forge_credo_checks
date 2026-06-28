defmodule ForgeCredoChecks.LargeStructTest do
  use Credo.Test.Case

  alias ForgeCredoChecks.LargeStruct

  defp struct_with(n) do
    fields = Enum.map_join(1..n, ", ", &":f#{&1}")

    """
    defmodule Sample do
      defstruct [#{fields}]
    end
    """
  end

  test "no issue: small struct" do
    struct_with(3)
    |> to_source_file()
    |> run_check(LargeStruct)
    |> refute_issues()
  end

  test "no issue: exactly 31 fields" do
    struct_with(31)
    |> to_source_file()
    |> run_check(LargeStruct)
    |> refute_issues()
  end

  test "issue: 32 fields (the boundary)" do
    struct_with(32)
    |> to_source_file()
    |> run_check(LargeStruct)
    |> assert_issue()
  end

  test "issue: 40-field keyword struct" do
    fields = Enum.map_join(1..40, ", ", &"f#{&1}: nil")

    """
    defmodule Sample do
      defstruct [#{fields}]
    end
    """
    |> to_source_file()
    |> run_check(LargeStruct)
    |> assert_issue()
  end

  test "no issue: defstruct from a module attribute cannot be counted" do
    """
    defmodule Sample do
      @fields [:a, :b, :c]
      defstruct @fields
    end
    """
    |> to_source_file()
    |> run_check(LargeStruct)
    |> refute_issues()
  end

  test "config: max_fields lowers the threshold" do
    struct_with(5)
    |> to_source_file()
    |> run_check(LargeStruct, max_fields: 5)
    |> assert_issue()
  end
end
