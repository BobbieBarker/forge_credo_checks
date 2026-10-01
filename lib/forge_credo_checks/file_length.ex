defmodule ForgeCredoChecks.FileLength do
  use Credo.Check,
    base_priority: :high,
    category: :design,
    param_defaults: [max_lines: 800, allowlist: []],
    explanations: [
      check: """
      Keep each source file at or under `max_lines` lines (800 by default). When
      a file grows past the limit, give a whole responsibility a module of its
      own, starting with the one the change added or extended, or report why
      the file should stay whole. Trimming the file to fit is not a fix.

      ## Why

      Coding agents commonly read a whole file before they edit it, so a file's
      length is a cost paid on every change to it. Elixir source tokenizes at
      about 8.6 tokens per line, measured on a production codebase with the
      GLM-5.3, Kimi-K3 and o200k tokenizers, which agree within 1%. An
      800-line file therefore costs about 7k tokens per whole-file read.

      The limit bounds the worst single read, and typical files sit well below
      it: in the measured Elixir codebase the median source file is 142 lines
      and the 90th percentile is 638. It is a ceiling, not a target size.
      Splitting a file below what a cohesive responsibility needs only adds
      files to every change's reading list.

      Length is a prompt to look at a module's design. It does not say where a
      boundary goes: a large module can be one cohesive responsibility, and a
      small one can mix unrelated ones. A useful boundary follows David
      Parnas's information hiding. Each module owns a design decision that is
      likely to change, such as a policy, a data format or how some state is
      stored, and hides it behind an interface, so callers ask for an outcome
      without knowing how it is produced. Judge a split by what callers must
      know before and after it, counting the new interface. If they must know
      as much as before, the split added a file and hid nothing.

      ## Splitting an oversized file

      1. Start from the change, and name the responsibility it adds or extends.
         A new concern, such as a policy, a data format, a client for an
         external service or a process with its own lifecycle, gets its own
         module in the same change, not in a follow-up. If the change created
         the file, every concern in it is new: give each one that changes for
         its own reasons a module, and stop when what remains is one
         responsibility, not when the count passes. If the change extends one
         of several responsibilities in the file, move that whole
         responsibility, not only the new part. If it extends the
         responsibility the file exists for, the new code stays with it: move
         out another responsibility that changes for its own reasons, or, if
         there is none, see the next section.
      2. Map the file before moving anything: what each group of functions
         does, which data it reads and writes, which invariants it keeps, and
         which groups change for the same reasons. Functions that run one after
         another, or that read the same input, do not form a responsibility for
         that reason alone.
      3. Define the interface first: what the module promises, what callers
         pass in, what they get back and how it fails. Callers should not need
         its data shapes, its storage or the order its functions must be called
         in. Pass the values its job needs. A domain struct the caller already
         holds is fine; the caller's whole state is not. A module that owns a
         timer, a process or a resource owns its whole lifecycle: matching
         replies to requests, ignoring stale messages, cancellation and cleanup
         after a failure. A pure decision, such as computing a retry delay, can
         move on its own while the process keeps the timer.
      4. Move the code without changing its behavior. Only the functions that
         form the new interface change shape, to take the inputs from step 3.
         Helpers that only the moved code uses go with it. A helper both
         modules need goes to the module that owns the knowledge it encodes.
         If the moved code would have to call back into the original module,
         keep that sequence of calls in the original, since coordinating them
         is its job, and move the rules or the representation the sequence
         relies on.
      5. Move the focused tests with the code and test the new module through
         its public interface. Keep the original module's tests of the behavior
         it promises as a whole, including its failures.
      6. Check the result. Callers should know less than before, and
         `mix xref graph --format cycles` should show no new cycle. In the
         commit or pull request, say what the new module owns and what its
         callers no longer need to know. "The file was too long" is not a
         reason.

      If the file is still over the limit, repeat with the responsibility whose
      reasons to change are most independent of the rest, never the one that
      saves the most lines.

      ## When the file should stay whole

      A file can be over the limit and still be one responsibility: a rule
      table whose clauses share one precedence order, a state machine, a data
      format with its parser and formatter. A change that extends such a
      responsibility belongs in it. If every split you can find leaves the
      parts sharing state, calling back and forth, updating in lockstep or
      depending on the order they are asked in, the file is better whole.

      Then do not split it. Keep the change, leave this check failing, and
      report the conflict where the change is reviewed: name the responsibility the file owns, each split you
      considered and why each one is worse. For example:

          lib/my_app/tax/state_rates.ex is 802 lines after this fix. It is one
          statute's rate table, and its clauses share one precedence order.
          Moving the grocery clauses out would make rate_for/2 decide when to
          ask the new module, which splits that order across two files. Moving
          the exemptions out has the same problem.

      Whether to accept the file as it is, by adding it to `allowlist`, is for
      the project's maintainers to decide after reading the report. The change
      that created or grew the file does not add the entry, and neither does a
      separate change made to get the check passing.

      ## What is not a fix

      * Adding the file to `allowlist`, raising `max_lines`, disabling the
        check in `.credo.exs` or with a `# credo:disable-for-this-file`
        comment, or excluding the file through Credo's `files` setting. Each
        one hides the file and leaves the design as it was.
      * Deleting `@moduledoc`, `@doc`, `@spec` or comments, removing blank
        lines, joining lines, collapsing functions into `do:` one-liners, or
        raising the formatter's `line_length`. The same design becomes harder
        to read.
      * Choosing what moves by how many lines it saves, where it sits in the
        file or when it runs: `Part2`, `Continued` or numbered modules, all
        callbacks in one module and all private functions in another, or
        whatever fits into `Helpers`, `Utils` or `Common`. Naming such a
        fragment after a responsibility does not help while the original
        module still implements part of it.
      * Making private functions public, with or without `@doc false`, so the
        moved code compiles, or letting the new module call back into the old
        one.
      * Passing the new module the whole state struct, `conn` or socket when
        it needs a few of their fields.
      * Rewriting code while moving it, or copying a shared helper into both
        modules. A rewrite hides behavior changes inside the move.
      * Moving functions into a `__using__/1` macro that injects them back
        into the same module, or moving code under `test/` or another path the
        check does not read.
      * Deleting or weakening tests, removing behavior, or shrinking or
        reverting the change.

      ## Bad

          # billing.ex passed the limit, so its last 400 lines moved to a second
          # file. The moved code needs Billing's private functions, so they
          # became public, and every function still takes the whole state.
          defmodule MyApp.Billing.Part2 do
            def charge_failed(%MyApp.Billing{} = state, invoice_id) do
              entry = MyApp.Billing.fetch_entry!(state, invoice_id)
              delay = MyApp.Billing.retry_delay(state, entry.attempts + 1)
              MyApp.Billing.schedule_retry(state, invoice_id, delay)
            end
          end

          # Whatever else did not fit: the invoice key format, which every
          # invoice operation still has to know, beside the late fee policy.
          defmodule MyApp.Billing.Helpers do
            def invoice_key(id), do: "invoice:" <> id

            def late_fee(%MyApp.Billing{} = state, amount),
              do: min(div(amount, 20), state.fee_cap)
          end

          # Some rate clauses moved out under a plausible name, but rate_for/2
          # still decides when to ask, so one precedence order spans two files.
          def rate_for(item, state) do
            case GroceryRates.lookup(item, state) do
              :no_match -> table_rate(item, state)
              rate -> rate
            end
          end

          # The file is silenced instead of split.
          {ForgeCredoChecks.FileLength,
           max_lines: 1_200, allowlist: ["lib/my_app/billing.ex"]}

          # credo:disable-for-this-file ForgeCredoChecks.FileLength

      ## Good

          # lib/my_app/billing/retry_schedule.ex: one policy with its own
          # reasons to change. It takes a failure count, returns a decision and
          # never sees the billing state.
          defmodule MyApp.Billing.RetrySchedule do
            @spec after_failure(pos_integer()) :: {:retry, pos_integer()} | :stop
            def after_failure(failures) when failures >= 5, do: :stop
            def after_failure(failures), do: {:retry, failures * 60}
          end

          # lib/my_app/billing/invoice_store.ex: the only module that knows how
          # invoice entries are keyed and what they hold.
          defmodule MyApp.Billing.InvoiceStore do
            @spec record_failure(t(), String.t()) :: {pos_integer(), t()}
            def record_failure(store, invoice_id) do
              key = "invoice:" <> invoice_id
              %{status: :open} = entry = Map.fetch!(store, key)
              attempts = entry.attempts + 1
              {attempts, Map.put(store, key, %{entry | attempts: attempts})}
            end
          end

          # lib/my_app/billing.ex runs the use case through both interfaces and
          # hands the store only its own part of the state. Billing still owns
          # the retry timer, so scheduling a retry and dropping a stale one stay
          # here.
          def charge_failed(state, invoice_id) do
            {failures, invoices} =
              InvoiceStore.record_failure(state.invoices, invoice_id)

            {RetrySchedule.after_failure(failures), %{state | invoices: invoices}}
          end

      ## What is flagged

      A source file with more than `max_lines` lines whose path is not in
      `allowlist`, and an allowlisted file that is at or under the limit, so
      that its entry gets removed (see Configuration). Lines are counted the
      way an editor numbers them, so a trailing newline does not add a line.
      Documentation, comments and blank lines all count, because a whole-file
      read pays for them too.

      Test files are not checked: a file ending in `_test.exs`, or any file
      under a `test/` directory.

      The issue is reported on line 1, where Credo reports issues that belong
      to a whole file. No single line is at fault, and the line where the
      count runs out is not where the fix goes. The message gives the file's
      line count and the limit.

      ## Configuration

      `max_lines` (default 800) is the most lines a checked file may have. It
      applies to every checked file; there are no per-file limits.

      `allowlist` (default `[]`) holds the paths of existing oversized files:
      files that were over the limit when the project adopted the check, and
      files a maintainer has decided to keep whole after a reported conflict.
      Paths are relative to the directory `mix credo` runs in, normally the
      project root, so write each one the way Credo prints it under the
      issue. Matching is exact: `"lib/my_app/legacy_importer.ex"` exempts that
      file and no other. It does not exempt a file with the same basename in
      another directory, a similarly named file such as
      `lib/my_app/legacy_importer_v2.ex`, or the files in a directory, and no
      entry is a wildcard. A leading `./` or the absolute path of the same file
      also matches. An entry exempts its file from this check only; every other
      check still runs on it.

          # .credo.exs, in the checks list
          {ForgeCredoChecks.FileLength,
           max_lines: 800,
           allowlist: [
             # Over the limit when the check was adopted. Delete each entry in
             # the change that brings its file within the limit.
             "lib/my_app/legacy_importer.ex",
             "lib/my_app/reports/monthly_report.ex"
           ]}

      Each entry is temporary. When a split brings a listed file to `max_lines`
      lines or fewer, delete its entry in the same change and run
      `mix credo --strict` to confirm the file passes. The check reports an
      entry whose file is at or under the limit until the entry is removed.
      The modules the split creates are new files and are checked like any
      other. Renaming or moving a listed file also ends its exemption: the old
      entry matches nothing and the file at its new path is checked, so delete
      the old entry. When the last entry is gone, delete the `allowlist` key.

          # lib/my_app/legacy_importer.ex is now 610 lines, so its entry goes.
          {ForgeCredoChecks.FileLength,
           max_lines: 800,
           allowlist: ["lib/my_app/reports/monthly_report.ex"]}
      """,
      params: [
        max_lines: "The most lines a checked file may have; one limit applies to every file.",
        allowlist:
          "Exact paths of existing oversized files, relative to where `mix credo` runs, exempt from this check only; no basenames, directories or wildcards."
      ]
    ]

  @test_file_patterns [~r{(^|[\\/])test[\\/]}, ~r/_test\.exs$/]

  @doc false
  @impl true
  @spec run(Credo.SourceFile.t(), Keyword.t()) :: [Credo.Issue.t()]
  def run(source_file, params \\ []) do
    max_lines = max_lines!(params)
    allowlist = allowlist!(params)

    if test_file?(source_file.filename) do
      []
    else
      source_file
      |> Credo.SourceFile.source()
      |> line_count()
      |> issues(
        max_lines,
        allowlisted?(source_file.filename, allowlist),
        IssueMeta.for(source_file, params)
      )
    end
  end

  defp max_lines!(params) do
    params
    |> Params.get(:max_lines, __MODULE__)
    |> validate_max_lines!()
  end

  defp validate_max_lines!(max_lines) when is_integer(max_lines) and max_lines > 0, do: max_lines

  defp validate_max_lines!(other) do
    raise ArgumentError,
          "#{inspect(__MODULE__)} :max_lines must be a positive integer, got: #{inspect(other)}"
  end

  defp allowlist!(params) do
    params
    |> Params.get(:allowlist, __MODULE__)
    |> expand_allowlist!()
  end

  defp expand_allowlist!(entries) when is_list(entries), do: Enum.map(entries, &expand_entry!/1)

  defp expand_allowlist!(other) do
    raise ArgumentError,
          "#{inspect(__MODULE__)} :allowlist must be a list of exact file paths, got: #{inspect(other)}"
  end

  defp expand_entry!(entry) when is_binary(entry), do: Path.expand(entry)

  defp expand_entry!(other) do
    raise ArgumentError,
          "#{inspect(__MODULE__)} :allowlist entries must be exact file paths (strings), " <>
            "not patterns; got: #{inspect(other)}"
  end

  defp test_file?(filename) when is_binary(filename),
    do: Enum.any?(@test_file_patterns, &(filename =~ &1))

  defp test_file?(_filename), do: false

  defp allowlisted?(filename, allowlist) when is_binary(filename),
    do: Path.expand(filename) in allowlist

  defp allowlisted?(_filename, _allowlist), do: false

  # Lines as an editor numbers them: a trailing newline ends the last line
  # rather than starting another one.
  defp line_count(""), do: 0

  defp line_count(source) do
    newlines = source |> :binary.matches("\n") |> length()

    if String.ends_with?(source, "\n"), do: newlines, else: newlines + 1
  end

  defp issues(lines, max_lines, false, issue_meta) when lines > max_lines,
    do: [oversized_issue(issue_meta, lines, max_lines)]

  defp issues(lines, max_lines, true, issue_meta) when lines <= max_lines,
    do: [stale_entry_issue(issue_meta, lines, max_lines)]

  defp issues(_lines, _max_lines, _allowlisted?, _issue_meta), do: []

  defp oversized_issue(issue_meta, lines, max_lines) do
    whole_file_issue(
      issue_meta,
      """
      This file has #{lines} lines; the limit is #{max_lines}. If this change adds or extends a \
      responsibility that can own its data, rules and call order (and the whole life of any \
      timer or process it starts), give it a module named for it so callers need to know less; \
      move its tests with it and keep this file's tests of the combined behavior. Move code this \
      change does not touch only while the file is still over the limit, one whole \
      responsibility at a time. A split is worse when the pieces need a dispatcher, a fixed call \
      order or each other's internals to work: if the file is one responsibility, like the \
      clauses of one rule table, keep your change, leave this check failing for a human, and say \
      what the file owns and which split you rejected. Not fixes: picking code by size, position \
      or when it runs; `Helpers`, `Utils` or `Part2` modules; passing the whole state; making \
      private functions public so a move compiles; trimming docs, comments or blank lines, or \
      joining lines; allowlisting or excluding the file, raising a limit, or disabling the \
      check. Examples: `mix credo explain ForgeCredoChecks.FileLength`.\
      """
    )
  end

  defp stale_entry_issue(issue_meta, lines, max_lines) do
    whole_file_issue(
      issue_meta,
      """
      This file has #{lines} lines, within the limit of #{max_lines}, but is still on the \
      `allowlist` of `ForgeCredoChecks.FileLength` in `.credo.exs`. Delete this file's entry \
      so the limit applies to it again, and leave the code, the other entries and the rest of \
      the configuration as they are.\
      """
    )
  end

  # Line 1, as Credo's own whole-file checks use: editor integrations drop an
  # issue with no line number, and SARIF output containing one fails validation.
  defp whole_file_issue(issue_meta, message) do
    format_issue(issue_meta, message: message, line_no: 1, trigger: Issue.no_trigger())
  end
end
