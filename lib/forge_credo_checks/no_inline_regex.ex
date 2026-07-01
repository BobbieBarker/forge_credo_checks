defmodule ForgeCredoChecks.NoInlineRegex do
  use Credo.Check,
    base_priority: :high,
    category: :readability,
    explanations: [
      check: """
      Define regex literals as module attributes instead of inline function-body sigils.

      ## Why

      Inline `~r` and `~R` sigils inside functions hide reusable parsing rules
      in implementation code. Module attributes give the pattern a name, keep
      related regexes near the top of the module, and make lexical searches for
      regex definitions reliable.

      ## Bad

          def valid?(value), do: value =~ ~r/^ok$/

          def valid?(value) do
            Regex.match?(~r/^ok$/, value)
          end

      ## Good

          @valid_value ~r/^ok$/

          def valid?(value), do: value =~ @valid_value
      """
    ]

  @function_defs [:def, :defp, :defmacro, :defmacrop]
  @regex_sigils [:sigil_r, :sigil_R]

  @doc false
  def run(source_file, params \\ []) do
    issue_meta = IssueMeta.for(source_file, params)
    Credo.Code.prewalk(source_file, &traverse(&1, &2, issue_meta))
  end

  defp traverse({def_type, _meta, [_head, clauses]} = ast, issues, issue_meta)
       when def_type in @function_defs and is_list(clauses) do
    new_issues =
      clauses
      |> Keyword.get(:do)
      |> issues_in_body(issue_meta)

    {ast, new_issues ++ issues}
  end

  defp traverse(ast, issues, _issue_meta), do: {ast, issues}

  defp issues_in_body(nil, _issue_meta), do: []

  defp issues_in_body(body, issue_meta) do
    {_body, issues} =
      Macro.prewalk(body, [], fn
        {sigil, meta, _args} = ast, issues when sigil in @regex_sigils ->
          {ast, [issue_for(issue_meta, sigil, meta) | issues]}

        ast, issues ->
          {ast, issues}
      end)

    issues
  end

  defp issue_for(issue_meta, sigil, meta) do
    trigger = trigger_for(sigil)

    format_issue(issue_meta,
      message:
        "Define regex literals in module attributes and reference the " <>
          "attribute from function bodies instead of using inline `#{trigger}` sigils.",
      trigger: trigger,
      line_no: Keyword.get(meta, :line)
    )
  end

  defp trigger_for(:sigil_r), do: "~r"
  defp trigger_for(:sigil_R), do: "~R"
end
