defmodule ForgeCredoChecks.MapNewFromInto do
  use Credo.Check,
    base_priority: :high,
    category: :refactor,
    explanations: [
      check: """
      Replace `Enum.into(%{}, fn ...)` with `Map.new/2`.

      ## Why

      `Map.new/2` is the idiomatic API for building a map from an enumerable
      with a transform function. `Enum.into(%{}, fn ...)` does the same work
      with awkward syntax that obscures the intent.

      ## How to fix

          # BEFORE
          enum |> Enum.into(%{}, fn {k, v} -> {String.downcase(k), v} end)

          # AFTER
          Map.new(enum, fn {k, v} -> {String.downcase(k), v} end)

      The transform function is identical; only the call site changes.

      Both nested and piped forms are flagged:

          Enum.into(enum, %{}, fn ... end)        # also flagged
          enum |> Enum.into(%{}, fn ... end)      # also flagged

      ## Note

      Stock Credo's `Refactor.MapInto` only catches `Enum.map |> Enum.into(%{})`.
      This check covers the direct `Enum.into(%{}, fn)` form Stock Credo misses.
      """
    ]

  @doc false
  def run(source_file, params \\ []) do
    issue_meta = IssueMeta.for(source_file, params)
    Credo.Code.prewalk(source_file, &traverse(&1, &2, issue_meta))
  end

  # Direct call form: Enum.into(enum, %{}, fn ...)
  defp traverse(
         {{:., _, [{:__aliases__, meta, [:Enum]}, :into]}, _, [_enum, {:%{}, _, []}, _fun]} = ast,
         issues,
         issue_meta
       ) do
    {ast, issues ++ List.wrap(issue_for(issue_meta, meta[:line]))}
  end

  # Piped form: enum |> Enum.into(%{}, fn ...)
  defp traverse(
         {:|>, _,
          [
            _,
            {{:., _, [{:__aliases__, meta, [:Enum]}, :into]}, _, [{:%{}, _, []}, _fun]}
          ]} = ast,
         issues,
         issue_meta
       ) do
    {ast, issues ++ List.wrap(issue_for(issue_meta, meta[:line]))}
  end

  defp traverse(ast, issues, _issue_meta), do: {ast, issues}

  defp issue_for(issue_meta, line_no) do
    format_issue(issue_meta,
      message:
        "Replace `Enum.into(%{}, fn ...)` with `Map.new(enum, fn ...)`. " <>
          "The transform function is identical; only the call site changes.",
      trigger: "Enum.into",
      line_no: line_no
    )
  end
end
