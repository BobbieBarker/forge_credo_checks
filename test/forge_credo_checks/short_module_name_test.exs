defmodule ForgeCredoChecks.ShortModuleNameTest do
  use Credo.Test.Case

  alias ForgeCredoChecks.ShortModuleName

  @lib_file "lib/my_app/billing.ex"
  @xy_message """
  `XY` in `MyApp.Billing.XY` is 2 characters; each segment of a module name needs at least 3. \
  Spell out what it abbreviates. If it is an acronym this domain already uses, leave this issue \
  for a human to add to `allowlist`. Not fixes: padding the name with letters or digits to reach \
  the minimum, or adding it to `allowlist` yourself. Examples: \
  `mix credo explain ForgeCredoChecks.ShortModuleName`.\
  """
  @ar_message """
  `AR`, the `as:` name for `MyApp.Accounts.Registration`, is 2 characters; an alias name needs \
  at least 3. Spell the name out, or drop `as:` if the module's own name reads well. If it is an \
  acronym this domain already uses, leave this issue for a human to add to `allowlist`. Not \
  fixes: padding the name with letters or digits to reach the minimum, or adding it to \
  `allowlist` yourself. Examples: `mix credo explain ForgeCredoChecks.ShortModuleName`.\
  """
  @min_length_error ~r/min_length/
  @allowlist_error ~r/allowlist/

  defp check(source, params \\ [], filename \\ @lib_file) do
    source
    |> to_source_file(filename)
    |> run_check(ShortModuleName, params)
  end

  defp triggers(issues), do: issues |> Enum.map(& &1.trigger) |> Enum.sort()

  describe "module name segments" do
    test "a two-character last segment is one issue naming the segment and the module" do
      """
      defmodule MyApp.Billing.XY do
      end
      """
      |> check()
      |> assert_issue(fn issue ->
        assert %Credo.Issue{
                 check: ShortModuleName,
                 category: :readability,
                 filename: @lib_file,
                 line_no: 1,
                 trigger: "XY"
               } = issue

        assert issue.message == @xy_message
      end)
    end

    test "a one-character segment is an issue" do
      """
      defmodule MyApp.A do
      end
      """
      |> check()
      |> assert_issue(fn issue ->
        assert %Credo.Issue{trigger: "A"} = issue
        assert issue.message =~ "is 1 character;"
      end)
    end

    test "a short segment in the middle of the name is an issue" do
      """
      defmodule MyApp.Ev.Handler do
      end
      """
      |> check()
      |> assert_issue(fn issue -> assert %Credo.Issue{trigger: "Ev"} = issue end)
    end

    test "a short root segment is an issue" do
      """
      defmodule Ox.Accounts do
      end
      """
      |> check()
      |> assert_issue(fn issue -> assert %Credo.Issue{trigger: "Ox"} = issue end)
    end

    test "each short segment is its own issue" do
      """
      defmodule MyApp.Ev.XY do
      end
      """
      |> check()
      |> assert_issues(fn issues -> assert triggers(issues) == ["Ev", "XY"] end)
    end

    test "segments at the minimum length pass" do
      """
      defmodule MyApp.API.Map do
      end
      """
      |> check()
      |> refute_issues()
    end

    test "a nested defmodule is checked by the name it is written with" do
      """
      defmodule MyApp.Billing do
        defmodule XY do
        end
      end
      """
      |> check()
      |> assert_issue(fn issue ->
        assert %Credo.Issue{trigger: "XY", line_no: 2} = issue
        assert issue.message =~ "`XY` in `XY` is 2 characters"
      end)
    end

    test "a __MODULE__-relative name checks its literal segments" do
      """
      defmodule MyApp.Billing do
        defmodule __MODULE__.XY do
        end
      end
      """
      |> check()
      |> assert_issue(fn issue ->
        assert %Credo.Issue{trigger: "XY"} = issue
        assert issue.message =~ "`XY` in `__MODULE__.XY`"
      end)
    end

    test "a defprotocol name is checked" do
      """
      defprotocol MyApp.XY do
        def name(value)
      end
      """
      |> check()
      |> assert_issue(fn issue -> assert %Credo.Issue{trigger: "XY"} = issue end)
    end

    test "a module named by an atom is not checked" do
      """
      defmodule :xy do
      end
      """
      |> check()
      |> refute_issues()
    end

    test "a Mix task module is not checked, because the task name fixes its segments" do
      """
      defmodule Mix.Tasks.Db.Reset do
        use Mix.Task
        def run(_args), do: :ok
      end
      """
      |> check()
      |> refute_issues()
    end

    test "an explicitly rooted Mix task module is not checked" do
      """
      defmodule Elixir.Mix.Tasks.Db.Reset do
        use Mix.Task
        def run(_args), do: :ok
      end
      """
      |> check()
      |> refute_issues()
    end

    test "only the first Elixir segment denotes the root namespace" do
      "defmodule Elixir.Elixir.Mix.Tasks.Db do end"
      |> check()
      |> assert_issue(fn issue -> assert %Credo.Issue{trigger: "Db"} = issue end)
    end
  end

  describe "alias names" do
    test "a short as: name is one issue naming the alias and its module" do
      """
      defmodule MyApp.Signup do
        alias MyApp.Accounts.Registration, as: AR
      end
      """
      |> check()
      |> assert_issue(fn issue ->
        assert %Credo.Issue{line_no: 2, trigger: "AR"} = issue
        assert issue.message == @ar_message
      end)
    end

    test "as: is found among the other alias options" do
      """
      defmodule MyApp.Signup do
        alias MyApp.Accounts.Registration, warn: false, as: AR
      end
      """
      |> check()
      |> assert_issue(fn issue -> assert %Credo.Issue{trigger: "AR"} = issue end)
    end

    test "the issue points to as: even when the target has the same segment" do
      """
      defmodule MyApp.Signup do
        alias MyApp.AR, as: AR
      end
      """
      |> check()
      |> assert_issue(fn issue ->
        assert %Credo.Issue{line_no: 2, column: 23, trigger: "AR"} = issue
      end)
    end

    test "a spelled-out as: name passes" do
      """
      defmodule MyApp.Signup do
        alias MyApp.Accounts.Registration, as: Enrollment
      end
      """
      |> check()
      |> refute_issues()
    end

    test "an alias without as: refers to a module named elsewhere and is not checked" do
      """
      defmodule MyApp.Signup do
        alias MyApp.Ev.XY
        alias MyApp.{Ox, Ev.Handler}
      end
      """
      |> check()
      |> refute_issues()
    end

    test "defimpl for: refers to a module named elsewhere and is not checked" do
      """
      defimpl String.Chars, for: MyApp.XY do
        def to_string(_value), do: ""
      end
      """
      |> check()
      |> refute_issues()
    end
  end

  describe "the default allowlist" do
    for name <- ~w(DB ID IO IP OS UI) do
      test "#{name} passes" do
        """
        defmodule MyApp.#{unquote(name)} do
        end
        """
        |> check()
        |> refute_issues()
      end
    end

    for version <- ~w(V1 V12) do
      test "the API version namespace #{version} passes" do
        """
        defmodule MyAppWeb.API.#{unquote(version)}.UserController do
        end
        """
        |> check()
        |> refute_issues()
      end
    end

    test "matching is exact and case-sensitive, so Db is an issue" do
      """
      defmodule MyApp.Db do
      end
      """
      |> check()
      |> assert_issue(fn issue -> assert %Credo.Issue{trigger: "Db"} = issue end)
    end

    test "a V without a version number is an issue" do
      """
      defmodule MyApp.V do
      end
      """
      |> check()
      |> assert_issue(fn issue -> assert %Credo.Issue{trigger: "V"} = issue end)
    end
  end

  describe "a configured allowlist" do
    test "an exact entry passes that segment" do
      """
      defmodule MyApp.Billing.XY do
      end
      """
      |> check(allowlist: ["XY"])
      |> refute_issues()
    end

    test "it replaces the default list" do
      """
      defmodule MyApp.IO do
      end
      """
      |> check(allowlist: ["XY"])
      |> assert_issue(fn issue -> assert %Credo.Issue{trigger: "IO"} = issue end)
    end

    test "a regex entry passes a segment it matches whole" do
      """
      defmodule MyApp.Billing.XY do
      end
      """
      |> check(allowlist: [~r/X./])
      |> refute_issues()
    end

    test "a regex entry that matches only part of a segment does not pass it" do
      """
      defmodule MyApp.Billing.XY do
      end
      """
      |> check(allowlist: [~r/X/])
      |> assert_issue(fn issue -> assert %Credo.Issue{trigger: "XY"} = issue end)
    end

    test "a regex entry keeps its modifiers" do
      """
      defmodule MyApp.Billing.Xy do
      end
      """
      |> check(allowlist: [~r/xy/i])
      |> refute_issues()
    end

    test "a regex can backtrack from a partial alternative to a whole match" do
      "defmodule MyApp.XY do end"
      |> check(allowlist: [~r/X|XY/])
      |> refute_issues()
    end

    test "extended regexes may end with a comment" do
      for regex <- [~r/XY # approved acronym/x, ~r/(?x)XY # approved acronym/] do
        "defmodule MyApp.XY do end"
        |> check(allowlist: [regex])
        |> refute_issues()

        "defmodule MyApp.XZ do end"
        |> check(allowlist: [regex])
        |> assert_issue(fn issue -> assert %Credo.Issue{trigger: "XZ"} = issue end)
      end
    end

    test "a regex keeps options that must occur at the start of the pattern" do
      "defmodule MyApp.XY do end"
      |> check(allowlist: [~r/(*UTF)(*UCP)XY/])
      |> refute_issues()
    end

    test "a regex may quote through the end of its pattern" do
      "defmodule MyApp.XY do end"
      |> check(allowlist: [~r/\QXY/])
      |> refute_issues()
    end

    test "a regex that accepts early must still match the whole segment" do
      "defmodule MyApp.XY do end"
      |> check(allowlist: [~r/X(*ACCEPT)/])
      |> assert_issue(fn issue -> assert %Credo.Issue{trigger: "XY"} = issue end)
    end

    test "leading regex control verbs keep their alternative scope" do
      "defmodule MyApp.XY do end"
      |> check(allowlist: [~r/(*FAIL)|XY/])
      |> refute_issues()

      "defmodule MyApp.XY do end"
      |> check(allowlist: [~r/(*PRUNE)XZ|XY/])
      |> assert_issue(fn issue -> assert %Credo.Issue{trigger: "XY"} = issue end)
    end

    test "the allowlist applies to as: names" do
      """
      defmodule MyApp.Signup do
        alias MyApp.Accounts.Registration, as: AR
      end
      """
      |> check(allowlist: ["AR"])
      |> refute_issues()
    end
  end

  describe "the minimum length" do
    test "a configured minimum replaces the default" do
      """
      defmodule MyApp.Map do
      end
      """
      |> check(min_length: 4)
      |> assert_issue(fn issue ->
        assert %Credo.Issue{trigger: "Map"} = issue
        assert issue.message =~ "is 3 characters; each segment of a module name needs at least 4."
      end)

      """
      defmodule MyApp.Repo do
      end
      """
      |> check(min_length: 4)
      |> refute_issues()
    end
  end

  describe "excluded paths" do
    for filename <- [
          "test/my_app/billing_test.exs",
          "test/support/fixtures.ex",
          "apps/core/test/core_test.exs"
        ] do
      test "#{filename} is not checked by default" do
        """
        defmodule MyApp.XY do
        end
        """
        |> check([], unquote(filename))
        |> refute_issues()
      end
    end

    test "excluded_paths: [] checks test files too" do
      """
      defmodule MyApp.XY do
      end
      """
      |> check([excluded_paths: []], "test/my_app/billing_test.exs")
      |> assert_issue(fn issue -> assert %Credo.Issue{trigger: "XY"} = issue end)
    end

    test "configured excluded paths replace the default" do
      source = """
      defmodule MyApp.XY do
      end
      """

      source
      |> check([excluded_paths: [~r"^lib/legacy/"]], "lib/legacy/report.ex")
      |> refute_issues()

      source
      |> check([excluded_paths: [~r"^lib/legacy/"]], "test/my_app/billing_test.exs")
      |> assert_issue(fn issue -> assert %Credo.Issue{trigger: "XY"} = issue end)
    end
  end

  describe "configuration errors" do
    for min_length <- [0, -1, 2.5, "3"] do
      test "min_length: #{inspect(min_length)} raises" do
        source = to_source_file("defmodule MyApp.Billing do\nend\n", @lib_file)

        assert_raise ArgumentError, @min_length_error, fn ->
          ShortModuleName.run(source, min_length: unquote(min_length))
        end
      end
    end

    test "an allowlist that is a single name instead of a list raises" do
      source = to_source_file("defmodule MyApp.Billing do\nend\n", @lib_file)

      assert_raise ArgumentError, @allowlist_error, fn ->
        ShortModuleName.run(source, allowlist: "XY")
      end
    end

    for entry <- ["MyApp.XY", "xy", "", :IO, 1] do
      test "the allowlist entry #{inspect(entry)} raises" do
        source = to_source_file("defmodule MyApp.Billing do\nend\n", @lib_file)

        assert_raise ArgumentError, @allowlist_error, fn ->
          ShortModuleName.run(source, allowlist: [unquote(entry)])
        end
      end
    end

    test "a malformed allowlist raises even in an excluded file" do
      source = to_source_file("defmodule MyApp.Billing do\nend\n", "test/my_app/billing_test.exs")

      assert_raise ArgumentError, @allowlist_error, fn ->
        ShortModuleName.run(source, allowlist: ["MyApp.XY"])
      end
    end
  end
end
