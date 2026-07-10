defmodule ForgeCredoChecks.MultilineStringConcat do
  use Credo.Check,
    base_priority: :high,
    category: :readability,
    explanations: [
      check: """
      Write wrapped string literals as a heredoc, not `<>`-concatenated lines.

      ## Why

      Splitting one constant string across several `<>` operators purely to
      wrap it in the source — `"line one " <> "line two " <> "line three"`
      written one operand per line — is runtime concatenation noise and an
      easy reviewer nit. A heredoc (`\"\"\"`) states the same literal in one
      form. When the wrapped lines must collapse into a single-line result, a
      trailing `\\` continues the line inside the heredoc without emitting a
      newline.

      This check fires only when *every* operand in the `<>` chain is a plain
      string literal and the chain spans more than one source line. A chain
      that folds in a variable or an interpolated string (`prefix <> name`,
      `"a" <> "b\#{x}"`) is dynamic assembly, not a wrapped constant, and is
      left alone. A single-line `<>` of literals is harmless and is not
      flagged either — the multi-line span is the trigger, not the operand
      count.

      ## Bad

          "the quick brown fox " <>
            "jumps over " <>
            "the lazy dog"

      ## Good

          # a genuinely multi-line string
          \"\"\"
          the quick brown fox
          jumps over
          the lazy dog
          \"\"\"

          # or, when the result must stay a single line, end each line with `\\`
          \"\"\"
          the quick brown fox \\
          jumps over \\
          the lazy dog\\
          \"\"\"
      """
    ]

  @doc false
  def run(source_file, params \\ []) do
    issue_meta = IssueMeta.for(source_file, params)
    Credo.Code.prewalk(source_file, &traverse(&1, &2, issue_meta))
  end

  # The first `<>` node prewalk reaches is the root of a maximal concatenation
  # chain: pre-order visits the outermost operator before any nested one. The
  # whole chain is analyzed here, then its spine is neutralized on return so the
  # inner `<>` operators are never visited independently — that is what keeps a
  # three-operand chain at exactly one issue instead of one per `<>`. Descent
  # still continues into the operand subtrees, so a separate literal chain
  # nested inside a non-literal operand keeps its own chance to be flagged.
  defp traverse({:<>, meta, [_left, _right]} = ast, issues, issue_meta) do
    if all_string_literals?(chain_operands(ast)) and multiline?(chain_operator_metas(ast)) do
      {neutralize(ast), [issue_for(issue_meta, meta[:line]) | issues]}
    else
      {neutralize(ast), issues}
    end
  end

  defp traverse(ast, issues, _issue_meta), do: {ast, issues}

  # Flatten the `<>` spine into its leaf operands. A nested `<>` is part of the
  # same chain and recurses; anything else is a leaf operand.
  defp chain_operands({:<>, _meta, [left, right]}) do
    chain_operands(left) ++ chain_operands(right)
  end

  defp chain_operands(operand), do: [operand]

  # Collect the metadata of every `<>` operator along the spine, for the
  # multi-line-span test.
  defp chain_operator_metas({:<>, meta, [left, right]}) do
    [meta | chain_operator_metas(left) ++ chain_operator_metas(right)]
  end

  defp chain_operator_metas(_operand), do: []

  # A plain string literal is a bare binary in the AST. An interpolated string
  # is a `{:<<>>, _, _}` node and a variable is a `{name, _, ctx}` node, so
  # neither is a binary and both correctly fail this guard.
  defp all_string_literals?(operands), do: Enum.all?(operands, &is_binary/1)

  # The chain spans multiple source lines when any operator is followed by a
  # newline before its right operand (a top-level `:newlines` key) or when the
  # operators do not all share one line. Single-line chains satisfy neither.
  defp multiline?(operator_metas) do
    Enum.any?(operator_metas, &Keyword.has_key?(&1, :newlines)) or
      operator_metas |> Enum.map(&Keyword.get(&1, :line)) |> Enum.uniq() |> length() > 1
  end

  # Rename the operator atom on every `<>` node along the spine so the nested
  # operators are not re-matched when prewalk descends, while leaving the
  # operand subtrees untouched so a concat nested inside a non-literal operand
  # still gets its own visit.
  defp neutralize({:<>, meta, [left, right]}) do
    {:__multiline_string_concat_seen__, meta, [neutralize(left), neutralize(right)]}
  end

  defp neutralize(operand), do: operand

  defp issue_for(issue_meta, line_no) do
    format_issue(issue_meta,
      message:
        "Multi-line string built by concatenating string literals with `<>`. " <>
          "Write it as a heredoc instead, using a trailing `\\` on each line " <>
          "if the result must stay a single line.",
      trigger: "<>",
      line_no: line_no
    )
  end
end
