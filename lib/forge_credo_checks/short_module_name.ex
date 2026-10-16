defmodule ForgeCredoChecks.ShortModuleName do
  use Credo.Check,
    base_priority: :normal,
    category: :readability,
    param_defaults: [
      min_length: 3,
      allowlist: ["DB", "ID", "IO", "IP", "OS", "UI", ~r/V\d+/],
      excluded_paths: [~r{(^|[\\/])test[\\/]}, ~r"_test\.exs$"]
    ],
    explanations: [
      check: """
      Spell out every segment of a module name. A segment shorter than
      `min_length` characters (3 by default) is almost always an abbreviation,
      and an abbreviated module name costs every reader who meets it.

      ## Why

      A module name is read far from where it was chosen: in aliases, call
      sites, stack traces, logs and docs. Unlike a variable it has no enclosing
      scope to explain it, so `Billing.XY` leaves every reader to work out what
      `XY` stands for, and the answer lives only with whoever named it. Coding
      agents shorten names this way, and a reviewer otherwise has to catch each
      one by hand.

      The minimum is low on purpose. A survey of compiled module names from
      Elixir 1.20.1, Credo 1.7.18, ExDoc 0.40.1, Dialyxir 1.4.7 and their
      dependencies (918 modules) found that the only
      segments shorter than 3 characters are `IO`, `UI`, `Do` and `Of`; with
      the defaults below, only `Module.Types.Of` would be flagged. Length is a
      proxy, not a spell checker: a 3-letter abbreviation such as `Rgx` passes.

      ## Bad

          defmodule MyApp.Billing.XY do
          end

          defmodule MyApp.Ev.Handler do
          end

          alias MyApp.Accounts.Registration, as: AR

      ## Good

          defmodule MyApp.Billing.ExchangeRate do
          end

          defmodule MyApp.Events.Handler do
          end

          alias MyApp.Accounts.Registration

      ## Not fixes

      Padding a name with letters or digits to reach the minimum (`XY` to `XYZ`
      or `Xy1`) keeps the abbreviation and only hides it from this check.
      Adding a name to `allowlist` is for acronyms the domain already uses, and
      that is a human's call: an agent should leave the issue in place and say
      what the name stands for.

      ## What is flagged

      Every segment of a `defmodule` or `defprotocol` name, and the name given
      by `alias ..., as:`. A name that only refers to a module (a plain
      `alias`, or `defimpl ..., for:`) is not flagged; it is checked where the
      module is defined. The segments of a `Mix.Tasks.*` module are not checked,
      because the task name typed at the command line fixes them (`mix
      db.reset` is `Mix.Tasks.Db.Reset`).

      Test files are skipped by default: a fixture module defined and used in
      one test file has the narrow scope in which a short name stays readable.

      ## Configuration

      `min_length` (default `3`) is the shortest segment that passes.

      `allowlist` names segments that pass at any length. An entry is either an
      exact segment (`"IO"`, case-sensitive) or a regex. A regex entry
      must match the whole segment: `~r/V\\d+/` passes `V1` and `V12`, and
      `~r/X/` does not pass `XY`. The default is `["DB", "ID", "IO", "IP",
      "OS", "UI", ~r/V\\d+/]`: common two-letter acronyms and API version
      namespaces.
      Setting `allowlist` replaces the default, so copy the entries you want to
      keep:

          {ForgeCredoChecks.ShortModuleName,
           allowlist: ["DB", "ID", "IO", "IP", "OS", "UI", ~r/V\\d+/, "QA"]}

      Entries are single segments, so `"MyApp.XY"` raises. To exempt one module
      rather than a name everywhere, use `# credo:disable-for-next-line`.

      `excluded_paths` lists path patterns (regexes or substrings) the check
      skips. The default excludes files under a `test/` directory and files
      ending in `_test.exs`; set it to `[]` to check tests too.
      """,
      params: [
        min_length: "The shortest module name segment that passes (default: 3).",
        allowlist:
          "Segments that pass at any length: exact strings or whole-segment regexes. " <>
            "Replaces the default list.",
        excluded_paths:
          "Paths skipped entirely (default: test/ directories and *_test.exs files)."
      ]
    ]

  @segment ~r/\A[A-Z][A-Za-z0-9_]*\z/
  @regex_start_options ~r/\A(?:\(\*(?!(?:ACCEPT|FAIL|F|COMMIT|PRUNE|SKIP|THEN)\))[A-Z][A-Z0-9_]*(?:=[0-9]+)?\))*/
  @not_fixes """
  If it is an acronym this domain already uses, leave this issue for a human to add to \
  `allowlist`. Not fixes: padding the name with letters or digits to reach the minimum, or \
  adding it to `allowlist` yourself. Examples: `mix credo explain ForgeCredoChecks.ShortModuleName`.\
  """

  @doc false
  @impl true
  @spec run(Credo.SourceFile.t(), Keyword.t()) :: [Credo.Issue.t()]
  def run(source_file, params \\ []) do
    rules = %{min_length: min_length!(params), allowlist: allowlist!(params)}

    if excluded_path?(source_file, params) do
      []
    else
      issue_meta = IssueMeta.for(source_file, params)
      Credo.Code.prewalk(source_file, &traverse(&1, &2, issue_meta, rules))
    end
  end

  defp min_length!(params) do
    params
    |> Params.get(:min_length, __MODULE__)
    |> validate_min_length!()
  end

  defp validate_min_length!(min_length) when is_integer(min_length) and min_length > 0,
    do: min_length

  defp validate_min_length!(other) do
    raise ArgumentError,
          "#{inspect(__MODULE__)} :min_length must be a positive integer, got: #{inspect(other)}"
  end

  defp allowlist!(params) do
    params
    |> Params.get(:allowlist, __MODULE__)
    |> validate_allowlist!()
  end

  defp validate_allowlist!(entries) when is_list(entries),
    do: Enum.map(entries, &allowlist_entry!/1)

  defp validate_allowlist!(other) do
    raise ArgumentError,
          "#{inspect(__MODULE__)} :allowlist must be a list of module name segments (strings) " <>
            "or regexes, got: #{inspect(other)}"
  end

  # Preserve start-only options such as (*UTF), leaving control verbs in their
  # original alternatives, before adding the anchors. Close
  # any trailing \Q quotation and extended-mode comment before the wrapper ends;
  # enabling extended mode there makes the added newline harmless in other modes.
  defp allowlist_entry!(%Regex{} = regex) do
    source = Regex.source(regex)
    [start_options] = Regex.run(@regex_start_options, source)
    pattern = String.replace_prefix(source, start_options, "")

    Regex.compile!(
      start_options <> "\\A(?:" <> pattern <> "\\E(?x)\r\n)\\z",
      Regex.opts(regex)
    )
  end

  defp allowlist_entry!(entry) when is_binary(entry) do
    if entry =~ @segment do
      entry
    else
      raise ArgumentError,
            "#{inspect(__MODULE__)} :allowlist entries are single module name segments " <>
              "like \"XY\", not full module names; got: #{inspect(entry)}"
    end
  end

  defp allowlist_entry!(other) do
    raise ArgumentError,
          "#{inspect(__MODULE__)} :allowlist entries must be module name segments (strings) " <>
            "or regexes, got: #{inspect(other)}"
  end

  defp excluded_path?(%{filename: filename}, params) when is_binary(filename) do
    params
    |> Params.get(:excluded_paths, __MODULE__)
    |> Enum.any?(&(filename =~ &1))
  end

  defp excluded_path?(_source_file, _params), do: false

  defp traverse(
         {definition, _meta, [{:__aliases__, meta, segments} = name | _]} = ast,
         issues,
         issue_meta,
         rules
       )
       when definition in [:defmodule, :defprotocol] do
    module_name = Macro.to_string(name)

    new_issues =
      for segment <- short_segments(segments, rules) do
        segment_issue(issue_meta, segment, module_name, meta, rules.min_length)
      end

    {ast, new_issues ++ issues}
  end

  defp traverse({:alias, _meta, [target, opts]} = ast, issues, issue_meta, rules)
       when is_list(opts) do
    {ast, alias_issues(Keyword.get(opts, :as), target, issue_meta, rules) ++ issues}
  end

  defp traverse(ast, issues, _issue_meta, _rules), do: {ast, issues}

  defp alias_issues({:__aliases__, meta, segments}, target, issue_meta, rules) do
    for name <- short_segments(segments, rules) do
      alias_issue(issue_meta, name, Macro.to_string(target), meta, rules.min_length)
    end
  end

  defp alias_issues(_as, _target, _issue_meta, _rules), do: []

  # Only the first Elixir segment is the implicit root namespace.
  defp short_segments([Elixir | segments], rules), do: short_literal_segments(segments, rules)
  defp short_segments(segments, rules), do: short_literal_segments(segments, rules)

  # A Mix task's module name is fixed by the task name typed at the command line
  # (`mix db.reset` is `Mix.Tasks.Db.Reset`), so it is not the author's to spell out.
  defp short_literal_segments([:Mix, :Tasks | _segments], _rules), do: []

  # Non-atom segments (`__MODULE__` in `__MODULE__.XY`) are not written names.
  defp short_literal_segments(segments, rules) do
    for segment <- segments,
        is_atom(segment),
        name = Atom.to_string(segment),
        short?(name, rules),
        do: name
  end

  defp short?(name, %{min_length: min_length, allowlist: allowlist}),
    do: String.length(name) < min_length and not Enum.any?(allowlist, &allowed?(&1, name))

  defp allowed?(%Regex{} = regex, name), do: Regex.run(regex, name, capture: :first) == [name]
  defp allowed?(entry, name), do: entry == name

  defp segment_issue(issue_meta, segment, module_name, meta, min_length) do
    format_issue(issue_meta,
      message: """
      `#{segment}` in `#{module_name}` is #{characters(segment)}; each segment of a module name \
      needs at least #{min_length}. Spell out what it abbreviates. #{@not_fixes}\
      """,
      trigger: segment,
      line_no: Keyword.get(meta, :line)
    )
  end

  defp alias_issue(issue_meta, name, target, meta, min_length) do
    format_issue(issue_meta,
      message: """
      `#{name}`, the `as:` name for `#{target}`, is #{characters(name)}; an alias name needs at \
      least #{min_length}. Spell the name out, or drop `as:` if the module's own name reads well. \
      #{@not_fixes}\
      """,
      trigger: name,
      line_no: Keyword.get(meta, :line),
      column: Keyword.get(meta, :column)
    )
  end

  defp characters(name), do: name |> String.length() |> pluralize_characters()

  defp pluralize_characters(1), do: "1 character"
  defp pluralize_characters(count), do: "#{count} characters"
end
