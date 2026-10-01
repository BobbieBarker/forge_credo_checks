defmodule ForgeCredoChecks.FileLengthTest do
  use Credo.Test.Case

  alias ForgeCredoChecks.{FileLength, FilterMap}

  @legacy "lib/my_app/legacy/billing.ex"
  @oversized_801_message """
  This file has 801 lines; the limit is 800. If this change adds or extends a responsibility \
  that can own its data, rules and call order (and the whole life of any timer or process it \
  starts), give it a module named for it so callers need to know less; move its tests with it \
  and keep this file's tests of the combined behavior. Move code this change does not touch only \
  while the file is still over the limit, one whole responsibility at a time. A split is worse \
  when the pieces need a dispatcher, a fixed call order or each other's internals to work: if \
  the file is one responsibility, like the clauses of one rule table, keep your change, leave \
  this check failing for a human, and say what the file owns and which split you rejected. Not \
  fixes: picking code by size, position or when it runs; `Helpers`, `Utils` or `Part2` modules; \
  passing the whole state; making private functions public so a move compiles; trimming docs, \
  comments or blank lines, or joining lines; allowlisting or excluding the file, raising a \
  limit, or disabling the check. Examples: `mix credo explain ForgeCredoChecks.FileLength`.\
  """
  @pattern_entry ~r/legacy/
  @max_lines_error ~r/max_lines/
  @allowlist_error ~r/allowlist/

  # Exactly `count` lines, each newline-terminated, as a valid module.
  defp source_with_lines(count) when count >= 2 do
    comments = Enum.map_join(1..(count - 2)//1, &"  # line #{&1}\n")
    "defmodule Sample do\n" <> comments <> "end\n"
  end

  defp file_with_lines(count, filename \\ "lib/my_app/orders.ex") do
    count
    |> source_with_lines()
    |> to_source_file(filename)
  end

  describe "the line limit" do
    test "a file exactly at the default limit of 800 lines has no issue" do
      800
      |> file_with_lines()
      |> run_check(FileLength)
      |> refute_issues()
    end

    test "one line over the default limit is one issue on the file, stating the count and the limit" do
      801
      |> file_with_lines()
      |> run_check(FileLength)
      |> assert_issue(fn issue ->
        assert %Credo.Issue{
                 check: FileLength,
                 category: :design,
                 filename: "lib/my_app/orders.ex",
                 line_no: 1
               } = issue

        assert issue.message == @oversized_801_message
      end)
    end

    test "a configured limit replaces the default" do
      50
      |> file_with_lines()
      |> run_check(FileLength, max_lines: 50)
      |> refute_issues()

      51
      |> file_with_lines()
      |> run_check(FileLength, max_lines: 50)
      |> assert_issue(fn issue ->
        assert issue.message =~ "51"
        assert issue.message =~ "50"
      end)
    end

    test "a configured limit above the default passes a file the default would flag" do
      1_000
      |> file_with_lines()
      |> run_check(FileLength, max_lines: 1_200)
      |> refute_issues()

      1_201
      |> file_with_lines()
      |> run_check(FileLength, max_lines: 1_200)
      |> assert_issue(fn issue ->
        assert issue.message =~ "1201"
        assert issue.message =~ "1200"
      end)
    end
  end

  describe "counting lines" do
    test "a final line without a trailing newline still counts" do
      800
      |> source_with_lines()
      |> String.trim_trailing("\n")
      |> to_source_file("lib/my_app/orders.ex")
      |> run_check(FileLength)
      |> refute_issues()

      801
      |> source_with_lines()
      |> String.trim_trailing("\n")
      |> to_source_file("lib/my_app/orders.ex")
      |> run_check(FileLength)
      |> assert_issue(&assert(&1.message =~ "801"))
    end

    test "blank lines count" do
      ("defmodule Sample do\n" <> String.duplicate("\n", 799) <> "end\n")
      |> to_source_file("lib/my_app/orders.ex")
      |> run_check(FileLength)
      |> assert_issue(&assert(&1.message =~ "801"))
    end

    test "documentation counts" do
      doc_lines = Enum.map_join(1..797, &"  line #{&1}\n")

      ~s'defmodule Sample do\n  @moduledoc """\n#{doc_lines}  """\nend\n'
      |> to_source_file("lib/my_app/orders.ex")
      |> run_check(FileLength)
      |> assert_issue(&assert(&1.message =~ "801"))
    end

    test "CRLF line endings count the same as LF" do
      800
      |> source_with_lines()
      |> String.replace("\n", "\r\n")
      |> to_source_file("lib/my_app/orders.ex")
      |> run_check(FileLength)
      |> refute_issues()

      801
      |> source_with_lines()
      |> String.replace("\n", "\r\n")
      |> to_source_file("lib/my_app/orders.ex")
      |> run_check(FileLength)
      |> assert_issue(&assert(&1.message =~ "801"))
    end

    test "an empty file has no issue" do
      ""
      |> to_source_file("lib/my_app/empty.ex")
      |> run_check(FileLength, max_lines: 1)
      |> refute_issues()
    end
  end

  describe "test files" do
    for filename <- [
          "test/my_app/orders_test.exs",
          "test/support/fixtures.ex",
          "apps/shop/test/shop/orders_test.exs",
          "lib/my_app/orders_test.exs"
        ] do
      test "#{filename} is not checked" do
        5_000
        |> file_with_lines(unquote(filename))
        |> run_check(FileLength)
        |> refute_issues()
      end
    end

    test "an allowlisted test file within the limit is not reported either" do
      10
      |> file_with_lines("test/my_app/orders_test.exs")
      |> run_check(FileLength, allowlist: ["test/my_app/orders_test.exs"])
      |> refute_issues()
    end
  end

  describe "the allowlist" do
    test "an empty allowlist enforces the limit" do
      801
      |> file_with_lines(@legacy)
      |> run_check(FileLength, allowlist: [])
      |> assert_issue()
    end

    test "an allowlisted oversized file has no issue" do
      5_000
      |> file_with_lines(@legacy)
      |> run_check(FileLength, allowlist: [@legacy])
      |> refute_issues()
    end

    test "an equally oversized file that is not on the allowlist is one issue" do
      5_000
      |> file_with_lines("lib/my_app/reports.ex")
      |> run_check(FileLength, allowlist: [@legacy])
      |> assert_issue(&assert(&1.filename == "lib/my_app/reports.ex"))
    end

    test "a newly added oversized file is not exempted by an existing allowlist" do
      801
      |> file_with_lines("lib/my_app/new_feature.ex")
      |> run_check(FileLength, allowlist: [@legacy, "lib/my_app/legacy/reports.ex"])
      |> assert_issue(&assert(&1.filename == "lib/my_app/new_feature.ex"))
    end

    for filename <- [
          "lib/my_app/billing.ex",
          "lib/my_app/other/billing.ex",
          "lib/my_app/legacy/billing_report.ex",
          "lib/my_app/legacy/billing.exs",
          "lib/my_app/legacy/legacy/billing.ex"
        ] do
      test "the entry does not exempt #{filename}" do
        5_000
        |> file_with_lines(unquote(filename))
        |> run_check(FileLength, allowlist: [@legacy])
        |> assert_issue()
      end
    end

    for entry <- [
          "billing.ex",
          "lib/my_app/legacy",
          "lib/my_app/legacy/",
          "lib/my_app/legacy/*.ex",
          "lib/**/billing.ex",
          "lib/my_app/legacy/billing"
        ] do
      test "the entry #{inspect(entry)} does not exempt #{@legacy}" do
        5_000
        |> file_with_lines(@legacy)
        |> run_check(FileLength, allowlist: [unquote(entry)])
        |> assert_issue()
      end
    end

    test "an entry written with a leading ./ or as an absolute path names the same file" do
      source_file = file_with_lines(5_000, @legacy)

      source_file
      |> run_check(FileLength, allowlist: ["./" <> @legacy])
      |> refute_issues()

      source_file
      |> run_check(FileLength, allowlist: [Path.expand(@legacy)])
      |> refute_issues()
    end

    test "removing the entry restores enforcement for that file" do
      source_file = file_with_lines(5_000, @legacy)

      source_file
      |> run_check(FileLength, allowlist: [@legacy])
      |> refute_issues()

      source_file
      |> run_check(FileLength, allowlist: [])
      |> assert_issue(&assert(&1.filename == @legacy))
    end

    test "an allowlisted file is still subject to every other check" do
      comments = Enum.map_join(1..1_000, &"  # line #{&1}\n")

      source_file =
        """
        defmodule Sample do
          def names(users) do
            users
            |> Enum.filter(& &1.active)
            |> Enum.map(& &1.name)
          end
        #{comments}end
        """
        |> to_source_file(@legacy)

      source_file
      |> run_check(FileLength, allowlist: [@legacy])
      |> refute_issues()

      source_file
      |> run_check(FilterMap)
      |> assert_issue()
    end
  end

  describe "stale allowlist entries" do
    test "an allowlisted file under the limit is reported so its entry is removed" do
      600
      |> file_with_lines(@legacy)
      |> run_check(FileLength, allowlist: [@legacy])
      |> assert_issue(fn issue ->
        assert %Credo.Issue{check: FileLength, filename: @legacy, line_no: 1} = issue

        assert issue.message == """
               This file has 600 lines, within the limit of 800, but is still on the \
               `allowlist` of `ForgeCredoChecks.FileLength` in `.credo.exs`. Delete this \
               file's entry so the limit applies to it again, and leave the code, the other \
               entries and the rest of the configuration as they are.\
               """
      end)
    end

    test "an allowlisted file exactly at the limit is reported as a stale entry" do
      800
      |> file_with_lines(@legacy)
      |> run_check(FileLength, allowlist: [@legacy])
      |> assert_issue(&assert(&1.message =~ "has 800 lines, within the limit of 800"))
    end

    test "staleness is judged against the configured limit" do
      source_file = file_with_lines(900, @legacy)

      source_file
      |> run_check(FileLength, allowlist: [@legacy])
      |> refute_issues()

      source_file
      |> run_check(FileLength, max_lines: 1_000, allowlist: [@legacy])
      |> assert_issue(&assert(&1.message =~ "has 900 lines, within the limit of 1000"))
    end

    test "a file under the limit that is not on the allowlist has no issue" do
      600
      |> file_with_lines("lib/my_app/orders.ex")
      |> run_check(FileLength, allowlist: [@legacy])
      |> refute_issues()
    end
  end

  describe "configuration errors" do
    for max_lines <- [0, -1, 800.0, "800"] do
      test "max_lines: #{inspect(max_lines)} raises" do
        source_file = file_with_lines(10)

        assert_raise ArgumentError, @max_lines_error, fn ->
          FileLength.run(source_file, max_lines: unquote(max_lines))
        end
      end
    end

    test "a pattern in the allowlist raises" do
      source_file = file_with_lines(10)

      assert_raise ArgumentError, @allowlist_error, fn ->
        FileLength.run(source_file, allowlist: [@pattern_entry])
      end
    end

    test "a non-path entry in the allowlist raises" do
      source_file = file_with_lines(10)

      assert_raise ArgumentError, @allowlist_error, fn ->
        FileLength.run(source_file, allowlist: [:billing])
      end
    end

    test "an allowlist that is a single path instead of a list raises" do
      source_file = file_with_lines(10)

      assert_raise ArgumentError, @allowlist_error, fn ->
        FileLength.run(source_file, allowlist: @legacy)
      end
    end

    test "a malformed allowlist raises even when an earlier entry matches" do
      source_file = file_with_lines(5_000, @legacy)

      assert_raise ArgumentError, @allowlist_error, fn ->
        FileLength.run(source_file, allowlist: [@legacy, @pattern_entry])
      end
    end
  end
end
