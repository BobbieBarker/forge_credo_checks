defmodule ForgeCredoChecks.NoTicketReferences do
  use Credo.Check,
    base_priority: :normal,
    category: :readability,
    param_defaults: [ticket_prefixes: []],
    explanations: [
      check: """
      Keep ticket references in Git history, not in comments or documentation.

      ## Why

      Comments should explain lasting constraints and why the code behaves as it
      does. Narration such as "added this for FGE-123" describes an edit rather
      than the code, grows stale, and gives reviewers avoidable cleanup work.
      A commit message such as `fix(FGE-123): preserve the retry deadline`, or a
      ticket-bearing branch name retained in merge history, records provenance
      where it belongs. `git blame` leads readers to the introducing commit.

      ## What comments and docs are for

      Comments and documentation are maintained parts of the product. Write for
      someone who has not read the ticket or this conversation.

      Comments explain non-obvious reasons, invariants, constraints and trade-offs
      that the code alone does not make clear. Avoid restating obvious operations.
      Documentation describes purpose, current behavior, the public contract and
      correct usage, including relevant inputs, outputs, errors and examples.

      Progress updates, editing plans, completion summaries and messages to the
      requester belong in the conversation. They do not belong in source comments
      or documentation. A useful test is whether the text will still help someone
      understand or use the code after the ticket and editing session are forgotten.

      ## Configuration

      Configure `ticket_prefixes` with the project keys you want to forbid:

          {ForgeCredoChecks.NoTicketReferences, ticket_prefixes: ["FGE", "PAY"]}

      This list is required and must not be empty. There are no built-in project
      prefixes. Each entry starts with an ASCII letter and contains only letters,
      digits or underscores; supply `"FGE"`, not `"FGE-"` or a regex.

      Matching is case-insensitive and requires a prefix, a hyphen and a numeric
      ticket number. With `"FGE"` configured, `FGE-123` and `fge-123` are flagged,
      including in links such as `/issue/FGE-123/fix` or `/FGE-123-description`.
      Embedded identifiers such as `AFGE-123` and `FGE-123abc` are not matched.
      Unconfigured prefixes, bare issue numbers and ordinary numbers are ignored.

      ## Bad

          # As requested, I added this guard for FGE-123; the tests now pass.
          @doc "This update implements FGE-123 by adding deadline-aware retries."

      ## Good

          # Retries share the original deadline so a failing peer cannot extend it.
          @doc "Retries transient failures within the original request deadline."

      Put the ticket in the commit message or branch history. Remove change
      narration, but preserve any useful explanation of why the code works this
      way. Deleting useful documentation or just removing the ticket number from
      otherwise unchanged narration is not the fix. Do not rename or split the
      ticket identifier, move it to another comment, or weaken the configured
      prefixes to make the warning disappear.

      ## Scope

      Checks actual `#` comments, including inline comments, and literal text in
      `@doc`, `@moduledoc` and `@typedoc`. Test files are included. Quoted strings,
      heredocs, `~s`/`~S` string sigils, concatenated literals and the literal
      portions of interpolated documentation are supported. Each occurrence is
      reported at its source location.

      Ordinary runtime strings, other attributes and documentation metadata such
      as `@doc since: "1.0"` are not checked. Documentation expressions are not
      evaluated: external files, attribute references and macro-generated text
      are outside this check. All matching references in the checked text are
      flagged, including examples and links; configuring a prefix is the policy.
      This check detects configured ticket identifiers; it does not attempt to
      classify all narration. The writing guidance describes how to fix a finding.
      """,
      params: [
        ticket_prefixes:
          ~s(Required nonempty list of project prefixes to forbid, e.g. ["FGE", "PAY"], ) <>
            "without the separating hyphen. Matching is case-insensitive."
      ]
    ]

  @prefix ~r/\A[A-Za-z][A-Za-z0-9_]*\z/
  @documentation [:doc, :moduledoc, :typedoc]
  @closing_delimiters %{"(" => ")", "[" => "]", "{" => "}", "<" => ">"}

  @doc false
  @impl true
  @spec run(Credo.SourceFile.t(), Keyword.t()) :: [Credo.Issue.t()]
  def run(source_file, params \\ []) do
    pattern = ticket_pattern!(params)
    source = Credo.SourceFile.source(source_file)

    case Regex.scan(pattern, source, return: :index, capture: :first) do
      [] -> []
      matches -> find_issues(source_file, source, matches, params)
    end
  end

  defp ticket_pattern!(params) do
    prefixes = Params.get(params, :ticket_prefixes, __MODULE__)

    if is_list(prefixes) and prefixes != [] and Enum.all?(prefixes, &valid_prefix?/1) do
      alternatives =
        prefixes |> Enum.uniq_by(&String.downcase/1) |> Enum.map_join("|", &Regex.escape/1)

      Regex.compile!(
        "(?<![\\p{L}\\p{M}\\p{N}_])(?:" <>
          alternatives <>
          ")-[0-9]+(?![\\p{L}\\p{M}\\p{N}_])",
        "iu"
      )
    else
      raise ArgumentError,
            "#{inspect(__MODULE__)} :ticket_prefixes must be a nonempty list of project keys " <>
              "such as [\"FGE\"], starting with a letter and containing only ASCII letters, " <>
              "digits or underscores (without the separating hyphen); got: #{inspect(prefixes)}"
    end
  end

  defp valid_prefix?(prefix) when is_binary(prefix), do: Regex.match?(@prefix, prefix)
  defp valid_prefix?(_prefix), do: false

  defp find_issues(source_file, source, matches, params) do
    case Code.string_to_quoted_with_comments(source,
           columns: true,
           token_metadata: true,
           unescape: false,
           emit_warnings: false,
           literal_encoder: &encode_literal/2
         ) do
      {:ok, ast, comments} ->
        context = source_context(source)
        ranges = Enum.sort(comment_ranges(comments, context) ++ doc_ranges(ast, context))
        issue_meta = IssueMeta.for(source_file, params)
        issues_in_ranges(matches, ranges, context, issue_meta)

      {:error, _reason} ->
        # Credo reports invalid source through its parser check.
        []
    end
  end

  defp encode_literal(literal, meta), do: {:ok, {:__literal__, meta, [literal]}}

  defp source_context(source) do
    {lines, _size} =
      source
      |> String.split("\n")
      |> Enum.map_reduce(0, fn line, offset ->
        {{offset, line}, offset + byte_size(line) + 1}
      end)

    %{source: source, lines: List.to_tuple(lines)}
  end

  defp comment_ranges(comments, context) do
    Enum.map(comments, fn comment ->
      start = source_offset(context, comment)
      {start, start + byte_size(comment.text)}
    end)
  end

  defp doc_ranges(ast, context) do
    {_ast, ranges} =
      Macro.prewalk(ast, [], fn
        {:@, _meta, [{attribute, _attribute_meta, [value]}]} = node, ranges
        when attribute in @documentation ->
          {node, documentation_ranges(value, context) ++ ranges}

        node, ranges ->
          {node, ranges}
      end)

    ranges
  end

  defp documentation_ranges({:__literal__, meta, [text]} = ast, context) when is_binary(text),
    do: literal_ranges(ast, meta, 0, context)

  defp documentation_ranges({:<<>>, meta, _parts} = ast, context),
    do: literal_ranges(ast, meta, 0, context)

  defp documentation_ranges({sigil, meta, [_body, _modifiers]} = ast, context)
       when sigil in [:sigil_s, :sigil_S],
       do: literal_ranges(ast, meta, 2, context)

  defp documentation_ranges({:<>, _meta, [left, right]}, context),
    do: documentation_ranges(left, context) ++ documentation_ranges(right, context)

  defp documentation_ranges(_expression, _context), do: []

  defp literal_ranges(ast, meta, sigil_size, context) do
    case Keyword.get(meta, :delimiter) do
      delimiter when is_binary(delimiter) ->
        start = source_offset(context, meta) + sigil_size + byte_size(delimiter)
        excluded = interpolation_ranges(ast, context)

        closing = %{
          delimiter: Map.get(@closing_delimiters, delimiter, delimiter),
          heredoc?: byte_size(delimiter) == 3,
          excluded: excluded
        }

        finish = closing_offset(context, start, closing)
        subtract_interpolations(start, finish, excluded)

      _delimiter ->
        []
    end
  end

  defp interpolation_ranges(ast, context) do
    {_ast, ranges} =
      Macro.prewalk(ast, [], fn
        {_name, meta, _args} = node, ranges when is_list(meta) ->
          if meta[:from_interpolation] && meta[:closing] do
            range = {source_offset(context, meta), source_offset(context, meta[:closing]) + 1}
            {node, [range | ranges]}
          else
            {node, ranges}
          end

        node, ranges ->
          {node, ranges}
      end)

    Enum.sort(ranges)
  end

  # Read source delimiters only after the parser identifies a documentation
  # literal. Decoded strings lose escapes and indentation, shifting diagnostics.
  defp closing_offset(context, offset, closing) do
    scope = {offset, byte_size(context.source) - offset}

    case :binary.match(context.source, closing.delimiter, scope: scope) do
      {position, length} ->
        if closing_delimiter?(context, position, closing) do
          position
        else
          closing_offset(context, position + length, closing)
        end

      :nomatch ->
        offset
    end
  end

  defp closing_delimiter?(context, position, closing) do
    not inside_ranges?(position, closing.excluded) and
      not escaped?(context.source, position - 1) and
      (not closing.heredoc? or indentation_only?(context, position))
  end

  defp inside_ranges?(position, ranges),
    do: Enum.any?(ranges, fn {start, finish} -> position >= start and position < finish end)

  defp escaped?(_source, position) when position < 0, do: false

  defp escaped?(source, position),
    do: :binary.at(source, position) == ?\\ and not escaped?(source, position - 1)

  defp indentation_only?(context, position) do
    {offset, line} = elem(context.lines, line_index(context.lines, position))
    line |> binary_part(0, position - offset) |> String.trim() == ""
  end

  defp subtract_interpolations(start, finish, excluded) do
    {cursor, ranges} =
      Enum.reduce(excluded, {start, []}, fn {from, to}, {cursor, ranges} ->
        ranges = if from > cursor, do: [{cursor, from} | ranges], else: ranges
        {max(cursor, to), ranges}
      end)

    if cursor < finish, do: [{cursor, finish} | ranges], else: ranges
  end

  defp issues_in_ranges([], _ranges, _context, _issue_meta), do: []
  defp issues_in_ranges(_matches, [], _context, _issue_meta), do: []

  defp issues_in_ranges(
         [[{offset, length}] | matches] = all_matches,
         [{start, finish} | ranges] = all_ranges,
         context,
         issue_meta
       ) do
    cond do
      offset < start ->
        issues_in_ranges(matches, all_ranges, context, issue_meta)

      offset >= finish ->
        issues_in_ranges(all_matches, ranges, context, issue_meta)

      offset + length <= finish ->
        [
          issue_for(context, issue_meta, offset, length)
          | issues_in_ranges(matches, all_ranges, context, issue_meta)
        ]

      true ->
        issues_in_ranges(matches, all_ranges, context, issue_meta)
    end
  end

  defp issue_for(context, issue_meta, offset, length) do
    line_index = line_index(context.lines, offset)
    {line_offset, line} = elem(context.lines, line_index)
    trigger = binary_part(context.source, offset, length)
    column = line |> binary_part(0, offset - line_offset) |> String.length() |> Kernel.+(1)

    format_issue(issue_meta,
      message:
        "Move `#{trigger}` to the commit message or branch history so git blame can find it. " <>
          "Comments should explain non-obvious reasons and constraints; " <>
          "docs should explain purpose, behavior, and how to use the code. " <>
          "Write for future readers without the ticket or conversation. " <>
          "Remove ticket references, change narration, and progress reports; preserve useful explanations.",
      trigger: trigger,
      line_no: line_index + 1,
      column: column
    )
  end

  defp source_offset(context, meta) do
    {offset, line} = elem(context.lines, meta[:line] - 1)
    offset + byte_size(String.slice(line, 0, meta[:column] - 1))
  end

  defp line_index(lines, offset), do: line_index(lines, offset, 0, tuple_size(lines) - 1)
  defp line_index(_lines, _offset, low, high) when low == high, do: low

  defp line_index(lines, offset, low, high) do
    middle = div(low + high + 1, 2)
    {line_offset, _line} = elem(lines, middle)

    if line_offset <= offset,
      do: line_index(lines, offset, middle, high),
      else: line_index(lines, offset, low, middle - 1)
  end
end
