defmodule ForgeCredoChecks.WithBareBinding do
  use Credo.Check,
    base_priority: :high,
    category: :refactor,
    explanations: [
      check: """
      Every clause in a `with` chain must use `<-`, never `=`.

      ## Why

      `<-` is what gives `with` its reason for existing: a non-match aborts
      the chain and returns the offending value as-is. A bare `=` line skips
      that fall-through behavior - it's a local binding smuggled into the
      chain to set up arguments for the next `<-` step. That bypasses the
      one piece of control flow `with` is supposed to provide.

      ## How to fix (two options)

      **Option 1 - bundle the infallible compute into the next fallible
      helper** so it emerges already wrapped in `{:ok, _} | {:error, _}` and
      the `with` chain consumes it via `<-`:

          # BAD
          with :ok <- verify(),
               argv = normalize_argv(raw_argv),
               {:ok, opts} <- parse_options(argv) do
            ...
          end

          # GOOD
          with :ok <- verify(),
               {:ok, opts} <- parse_options(raw_argv) do
            ...
          end

          defp parse_options(raw_argv) do
            raw_argv |> normalize_argv() |> OptionParser.parse(strict: @spec) |> ...
          end

      **Option 2 - move the binding into the `do` block.** The `do` block is
      normal Elixir code, so plain `=` bindings belong there. Use this when
      the binding only feeds the body, not later `with` steps:

          with :ok <- verify(),
               {:ok, opts} <- parse_options(raw_argv) do
            display = format_for_display(opts)
            {:ok, display}
          end

      ## What NOT to do

      Do not "fix" this by wrapping the bare compute in `{:ok, ...}` inline
      just to satisfy `<-`:

          # STILL BAD - fake fallibility, no real control flow
          with :ok <- verify(),
               {:ok, argv} <- {:ok, normalize_argv(raw_argv)},
               ...

      If the step can't fail, it doesn't belong as a `<-` step. Pick one of
      the two options above.
      """
    ]

  @doc false
  def run(source_file, params \\ []) do
    issue_meta = IssueMeta.for(source_file, params)
    Credo.Code.prewalk(source_file, &traverse(&1, &2, issue_meta))
  end

  defp traverse({:with, _meta, args} = ast, issues, issue_meta) when is_list(args) do
    new_issues =
      args
      |> Enum.drop(-1)
      |> Enum.flat_map(&issue_for_clause(&1, issue_meta))

    {ast, issues ++ new_issues}
  end

  defp traverse(ast, issues, _issue_meta), do: {ast, issues}

  defp issue_for_clause({:=, meta, [lhs, _rhs]}, issue_meta) do
    name = pattern_label(lhs)

    [
      format_issue(issue_meta,
        message:
          "`with` clause uses `=` to bind #{name}; clauses must use `<-`. " <>
            "Fix: either (1) extract a helper that performs this compute and " <>
            "returns `{:ok, _} | {:error, _}` so the next step binds it via `<-`, " <>
            "or (2) move this binding into the `do` block if it only feeds the body. " <>
            "Do NOT wrap it in `{:ok, ...}` inline just to satisfy `<-` - that's fake fallibility.",
        trigger: "=",
        line_no: meta[:line]
      )
    ]
  end

  defp issue_for_clause(_, _), do: []

  defp pattern_label({var, _, ctx}) when is_atom(var) and is_atom(ctx) do
    "`#{var}`"
  end

  defp pattern_label(_), do: "this value"
end
