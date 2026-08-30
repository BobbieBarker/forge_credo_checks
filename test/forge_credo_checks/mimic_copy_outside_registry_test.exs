defmodule ForgeCredoChecks.MimicCopyOutsideRegistryTest do
  use Credo.Test.Case

  alias ForgeCredoChecks.MimicCopyOutsideRegistry

  test "issue: Mimic.copy in a test file" do
    """
    defmodule FooTest do
      use ExUnit.Case
      Mimic.copy(SomeModule)
    end
    """
    |> to_source_file("test/forge_symphony/foo_test.exs")
    |> run_check(MimicCopyOutsideRegistry)
    |> assert_issue()
  end

  test "issue: a bare copy/1 reached through use Mimic" do
    """
    defmodule FooTest do
      use Mimic
      copy(SomeModule)
    end
    """
    |> to_source_file("test/forge_symphony/foo_test.exs")
    |> run_check(MimicCopyOutsideRegistry)
    |> assert_issue()
  end

  test "issue: a bare copy/1 reached through import Mimic" do
    """
    defmodule FooTest do
      import Mimic
      copy(SomeModule)
    end
    """
    |> to_source_file("test/forge_symphony/foo_test.exs")
    |> run_check(MimicCopyOutsideRegistry)
    |> assert_issue()
  end

  test "issue: a &Mimic.copy/1 capture outside the registration point" do
    """
    defmodule FooTest do
      def register, do: Enum.each([SomeModule], &Mimic.copy/1)
    end
    """
    |> to_source_file("test/forge_symphony/foo_test.exs")
    |> run_check(MimicCopyOutsideRegistry)
    |> assert_issue()
  end

  test "issue message names the registry to use instead" do
    """
    defmodule FooTest do
      Mimic.copy(SomeModule)
    end
    """
    |> to_source_file("test/forge_symphony/foo_test.exs")
    |> run_check(MimicCopyOutsideRegistry)
    |> assert_issue(fn issue ->
      assert issue.message =~ "ForgeSymphony.MockingGuide.mimic_modules/0"
      assert issue.message =~ "coexistence check"
    end)
  end

  test "no issue: the registration point itself" do
    """
    Enum.each(ForgeSymphony.MockingGuide.mimic_modules(), &Mimic.copy/1)
    """
    |> to_source_file("test/test_helper.exs")
    |> run_check(MimicCopyOutsideRegistry)
    |> refute_issues()
  end

  test "no issue: prose naming the function in a moduledoc" do
    ~S'''
    defmodule ForgeSymphony.MockingGuide do
      @moduledoc """
      Returns the modules `test/test_helper.exs` registers with `Mimic.copy/1`.
      """

      @doc "Registered with `Mimic.copy/1` at boot."
      def mimic_modules, do: []
    end
    '''
    |> to_source_file("test/support/mocking_guide.ex")
    |> run_check(MimicCopyOutsideRegistry)
    |> refute_issues()
  end

  test "no issue: a comment naming the function" do
    """
    defmodule FooTest do
      # Mimic.copy(SomeModule) belongs in test_helper.exs
      def noop, do: :ok
    end
    """
    |> to_source_file("test/forge_symphony/foo_test.exs")
    |> run_check(MimicCopyOutsideRegistry)
    |> refute_issues()
  end

  test "no issue: a bare copy/1 in a file that does not use Mimic" do
    """
    defmodule FooTest do
      def copy(thing), do: thing
      def run, do: copy(:ok)
    end
    """
    |> to_source_file("test/forge_symphony/foo_test.exs")
    |> run_check(MimicCopyOutsideRegistry)
    |> refute_issues()
  end

  test "no issue: outside the included paths" do
    """
    defmodule Foo do
      def register, do: Mimic.copy(SomeModule)
    end
    """
    |> to_source_file("lib/forge_symphony/foo.ex")
    |> run_check(MimicCopyOutsideRegistry)
    |> refute_issues()
  end
end
