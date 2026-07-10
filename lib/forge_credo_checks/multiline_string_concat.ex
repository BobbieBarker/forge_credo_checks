defmodule ForgeCredoChecks.MultilineStringConcat do
  use Credo.Check,
    base_priority: :normal,
    category: :readability,
    explanations: [
      check: """
      Replace multi-line string-literal `<>` concatenation with a heredoc.

      ## Why

      Assembling a wrapped string literal with `"..." <> "..." <> "..."` spread
      across source lines is unidiomatic noise. Elixir heredocs (`\"\"\" ... \"\"\"`)
      are the clean form for multi-line string literals; the `<>`-per-line pattern
      is a reviewer nit that signals an author reached for concatenation instead
      of the language's built-in multi-line string syntax.

      This check fires only when **every** operand of the `<>` chain is a plain
      string literal **and** the chain spans more than one source line. A
      `<>` that mixes in a variable or expression is legitimate interpolation
      avoidance or dynamic assembly and is not flagged; a single-line `<>` of
      literals is rare but harmless and is not flagged either.

      ## How to fix

          # BEFORE
          "first line " <>
          "second line " <>
          "third line"

          # AFTER
          \"\"\"
          first line second line third line
          \"\"\"

      When the concatenation is used to keep a single-line result under the line
      length limit, use a heredoc with a trailing-backslash line continuation:

          \"\"\"
          first line second line third line\\
          \"\"\"

      ## What NOT to do

      Do not disable this check for a `<>` chain that mixes a literal with a
      variable (`"prefix " <> some_var`). That form is intentionally out of
      scope: it is not a static string literal and may be avoiding interpolation
      for performance or readability reasons.
      """
    ]

  @doc false
  def run(source_file, params \\ []) do
    issue_meta = IssueMeta.for(source_file, params)
    # String literals are bare binaries in the AST and carry no `:line` metadata,
    # so the line span of a `<>` chain cannot be recovered from the AST alone.
    # Tokenize the source once and collect the line number of every string
    # literal token in source order; the traverse step matches these to a
    # chain's operands in order to determine whether the chain spans lines.
    string_lines = string_token_lines(source_file)
    Credo.Code.prewalk(source_file, &traverse(&1, &2, issue_meta, string_lines))
  end

  defp traverse({:<>, meta, [_left, _right]} = ast, issues, issue_meta, string_lines) do
    operands = flatten_concat(ast)

    if all_string_literals?(operands) and multi_line?(operands, string_lines) do
      # Neutralize the matched subtree (the same technique
      # `port_producer_boundary.ex` uses to neutralize function captures) so the
      # inner `<>` nodes of a longer chain are not re-matched by prewalk and the
      # chain produces one issue instead of one per `<>` node.
      {:__concatenated_string_literals__, [issue_for(issue_meta, meta[:line]) | issues]}
    else
      {ast, issues}
    end
  end

  defp traverse(ast, issues, _issue_meta, _string_lines), do: {ast, issues}

  # Flatten a nested `<>` chain into its leaf operands in source order.
  defp flatten_concat({:<>, _, [left, right]}), do: flatten_concat(left) ++ flatten_concat(right)

  defp flatten_concat(operand), do: [operand]

  # A plain string literal is a bare binary in the AST. An interpolated string
  # (`"a#{x}"`) is a `{:<<>>, _, _}` node and is therefore NOT a static literal.
  defp all_string_literals?(operands), do: Enum.all?(operands, &is_binary/1)

  # Determine whether a chain of string-literal operands spans more than one
  # source line. Because the operands are bare binaries without line metadata,
  # the line of each operand is recovered from the ordered list of string-token
  # line numbers collected from the source: the first operand consumes the next
  # matching token line, and so on. A single-line chain has all operands on one
  # line.
  defp multi_line?(operands, string_lines) do
    {lines, _rest} =
      Enum.map_reduce(operands, string_lines, fn operand, acc ->
        {line, new_acc} = next_line_for(operand, acc)
        {line, new_acc}
      end)

    lines
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
    |> length() > 1
  end

  # Find the line of the next string-token whose value matches the operand.
  # Tokens are in source order, so the first match is the right one.
  defp next_line_for(operand, [{line, value} | rest]) do
    if value == operand do
      {line, rest}
    else
      next_line_for(operand, rest)
    end
  end

  defp next_line_for(_operand, []), do: {nil, []}

  # Collect the line number and value of every plain string-literal token in
  # source order. Only `:bin_string` tokens (double-quoted, non-interpolated
  # string literals) are collected; heredocs (`:bin_heredoc`) and interpolated
  # strings (which tokenize as `:bin_string` containing interpolation) are
  # excluded so they do not confuse operand matching.
  defp string_token_lines(source_file) do
    source_file
    |> Credo.Code.to_tokens()
    |> Enum.flat_map(fn
      {:bin_string, {line, _col, _}, [value]} when is_binary(value) ->
        [{line, value}]

      _ ->
        []
    end)
  end

  defp issue_for(issue_meta, line_no) do
    format_issue(issue_meta,
      message: "Replace multi-line string-literal `<>` concatenation with a heredoc.",
      trigger: "<>",
      line_no: line_no
    )
  end
end
