defmodule ForgeCredoChecks.NoTicketReferencesTest do
  use Credo.Test.Case

  alias ForgeCredoChecks.NoTicketReferences

  @filename "lib/my_app/worker.ex"
  @configuration_error ~r/ticket_prefixes/

  defp check(source, params \\ [ticket_prefixes: ["FGE"]], filename \\ @filename) do
    source
    |> to_source_file(filename)
    |> run_check(NoTicketReferences, params)
  end

  test "flags a ticket in a standalone comment and explains the durable fix" do
    "# FGE-123: added retries for this ticket\n"
    |> check()
    |> assert_issue(fn issue ->
      assert %Credo.Issue{
               check: NoTicketReferences,
               category: :readability,
               filename: @filename,
               trigger: "FGE-123",
               line_no: 1,
               column: 3
             } = issue

      assert issue.message =~ "commit message"
      assert issue.message =~ "git blame"
      assert issue.message =~ "Comments should explain non-obvious reasons and constraints"
      assert issue.message =~ "docs should explain purpose, behavior, and how to use the code"
      assert issue.message =~ "future readers"
      assert issue.message =~ "ticket or conversation"
      assert issue.message =~ "change narration"
      assert issue.message =~ "progress reports"
      assert issue.message =~ "preserve useful explanations"
    end)
  end

  test "points to the inline comment rather than the same ticket in executable code" do
    ~S|value = "FGE-123" # FGE-123 added this|
    |> check()
    |> assert_issue(fn issue ->
      assert %Credo.Issue{line_no: 1, column: 21, trigger: "FGE-123"} = issue
    end)
  end

  test "reports every reference at its own location" do
    "# FGE-123 FGE-123\n# PAY-42\n"
    |> check(ticket_prefixes: ["FGE", "PAY"])
    |> assert_issues(fn issues ->
      assert Enum.map(issues, &{&1.trigger, &1.line_no, &1.column}) == [
               {"FGE-123", 1, 3},
               {"FGE-123", 1, 11},
               {"PAY-42", 2, 3}
             ]
    end)
  end

  test "matching is case-insensitive and supports digits and underscores in configured prefixes" do
    "# fge-123 TEAM2-4 TEAM_X-5\n"
    |> check(ticket_prefixes: ["fGe", "TEAM2", "TEAM_X"])
    |> assert_issues(fn issues ->
      assert Enum.map(issues, & &1.trigger) == ["fge-123", "TEAM2-4", "TEAM_X-5"]
    end)
  end

  test "flags configured ticket IDs inside links and branch names" do
    "# https://linear.app/team/issue/FGE-123/description FGE-456-title fix/FGE-789\n"
    |> check()
    |> assert_issues(fn issues ->
      assert Enum.map(issues, & &1.trigger) == ["FGE-123", "FGE-456", "FGE-789"]
    end)
  end

  test "does not infer unconfigured prefixes, bare issue numbers, or standard identifiers" do
    "# PAY-42, issue #123, RFC-9110, UTF-8, and ISO-8601\n"
    |> check()
    |> refute_issues()
  end

  test "a configured standard-like prefix is still forbidden" do
    "# UTF-8\n"
    |> check(ticket_prefixes: ["UTF"])
    |> assert_issue(fn issue -> assert %Credo.Issue{trigger: "UTF-8"} = issue end)
  end

  test "requires a complete numeric ticket identifier" do
    "# AFGE-123 _FGE-123 FGE-123abc FGE-123_foo FGE-ABC FGE- FGE-１２３ éFGE-123 FGE-123é\n"
    |> check()
    |> refute_issues()
  end

  test "duplicate prefixes do not duplicate issues" do
    "# FGE-123\n"
    |> check(ticket_prefixes: ["FGE", "fge", "FGE"])
    |> assert_issue()
  end

  test "columns use source characters rather than UTF-8 byte offsets" do
    "# café é 🐈 FGE-123\n"
    |> check()
    |> assert_issue(fn issue ->
      assert %Credo.Issue{line_no: 1, column: 12, trigger: "FGE-123"} = issue
    end)
  end

  test "test files are checked too" do
    "# FGE-123: added this test\n"
    |> check([ticket_prefixes: ["FGE"]], "test/worker_test.exs")
    |> assert_issue()
  end

  for attribute <- [:doc, :moduledoc, :typedoc] do
    test "flags a literal @#{attribute} string" do
      "@#{unquote(attribute)} \"Added in FGE-123\"\n"
      |> check()
      |> assert_issue(fn issue ->
        assert %Credo.Issue{trigger: "FGE-123", line_no: 1} = issue
      end)
    end

    test "ignores @#{attribute} metadata and false" do
      "@#{unquote(attribute)} since: \"FGE-123\"\n@#{unquote(attribute)} false\n"
      |> check()
      |> refute_issues()
    end
  end

  test "heredoc issues point at the actual text, including repeated tickets" do
    ~S'''
    defmodule MyApp do
      @moduledoc """
      Added in FGE-123.
        Followed by FGE-123.
      """
    end
    '''
    |> check()
    |> assert_issues(fn issues ->
      assert Enum.map(issues, &{&1.line_no, &1.column}) == [{3, 12}, {4, 17}]
    end)
  end

  test "escaped quotes before a ticket do not shift its reported column" do
    ~S|@doc "Say \"hello\"; FGE-123"|
    |> check()
    |> assert_issue(fn issue ->
      assert %Credo.Issue{line_no: 1, column: 22, trigger: "FGE-123"} = issue
    end)
  end

  test "strings after a documentation attribute are not documentation" do
    ~S|@doc "Useful text"; value = "FGE-123"|
    |> check()
    |> refute_issues()
  end

  test "escaped closing delimiters do not end the documentation early" do
    ~S|@doc ~S(Foo \) FGE-123)|
    |> check()
    |> assert_issue()
  end

  for source <- [
        ~S|@doc ~s(FGE-123)|,
        ~S|@doc ~S[FGE-123]|,
        ~S|@doc ~S{FGE-123}|,
        ~S|@doc ~S<FGE-123>|,
        ~S|@doc ~S/FGE-123/|
      ] do
    test "checks the string sigil #{source}" do
      unquote(source) |> check() |> assert_issue()
    end
  end

  test "checks heredoc sigils and allows embedded triple quotes" do
    ~S'''
    @doc ~S"""
    An inline """ delimiter precedes FGE-123.
    """
    '''
    |> check()
    |> assert_issue(fn issue ->
      assert %Credo.Issue{line_no: 2, trigger: "FGE-123"} = issue
    end)
  end

  test "checks both sides of concatenated documentation without evaluating code" do
    ~S|@doc "FGE-123" <> "FGE-456"|
    |> check()
    |> assert_issues(fn issues ->
      assert Enum.map(issues, & &1.trigger) == ["FGE-123", "FGE-456"]
    end)
  end

  test "checks literal interpolation text but not strings in interpolation code" do
    ~S|@doc "FGE-123 #{render("FGE-456")} FGE-789"|
    |> check()
    |> assert_issues(fn issues ->
      assert Enum.map(issues, & &1.trigger) == ["FGE-123", "FGE-789"]
    end)
  end

  test "comments inside documentation interpolation are still comments" do
    ~S'''
    @doc """
    #{
      # FGE-123 introduced this
      "FGE-456"
    }
    FGE-789 changed this.
    """
    '''
    |> check()
    |> assert_issues(fn issues ->
      assert Enum.map(issues, &{&1.trigger, &1.line_no}) == [{"FGE-123", 3}, {"FGE-789", 6}]
    end)
  end

  test "ignores ordinary strings, charlists, sigils, attributes, and external doc paths" do
    ~S'''
    value = "# FGE-123"
    chars = '# FGE-123'
    regex = ~r/# FGE-123/
    string = ~S"""
    # FGE-123
    """
    @example "FGE-123"
    @doc File.read!("FGE-123.md")
    @doc render("FGE-123")
    '''
    |> check()
    |> refute_issues()
  end

  test "a real comment after a string sigil is checked" do
    ~S|value = ~S[# FGE-123] # FGE-456|
    |> check()
    |> assert_issue(fn issue -> assert %Credo.Issue{trigger: "FGE-456"} = issue end)
  end

  test "CRLF source preserves line and column positions" do
    ~s(@doc """\r\n  FGE-123\r\n  """\r\n# FGE-456\r\n)
    |> check()
    |> assert_issues(fn issues ->
      assert Enum.map(issues, &{&1.trigger, &1.line_no, &1.column}) == [
               {"FGE-123", 2, 3},
               {"FGE-456", 4, 3}
             ]
    end)
  end

  test "missing prefixes fail with an actionable configuration error" do
    source = to_source_file("value = :ok\n", @filename)

    assert_raise ArgumentError, @configuration_error, fn ->
      NoTicketReferences.run(source)
    end
  end

  for prefixes <- [[], nil, "FGE", [:FGE], [""], [" "], ["FGE-"], ["F.GE"], ["FGE|PAY"], [123]] do
    test "rejects invalid ticket_prefixes #{inspect(prefixes)}" do
      source = to_source_file("value = :ok\n", @filename)

      assert_raise ArgumentError, @configuration_error, fn ->
        NoTicketReferences.run(source, ticket_prefixes: unquote(Macro.escape(prefixes)))
      end
    end
  end
end
