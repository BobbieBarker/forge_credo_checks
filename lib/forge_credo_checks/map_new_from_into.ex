defmodule ForgeCredoChecks.MapNewFromInto do
  use Credo.Check,
    base_priority: :high,
    category: :refactor,
    explanations: [
      check: """
      `Map.new/2` is the idiomatic API for building a map from an enumerable
      with a transform function. `Enum.into(%{}, fn ...)` does the same work
      with awkward syntax that obscures the intent.

      This:

          enum
          |> Enum.into(%{}, fn {k, v} -> {String.downcase(k), v} end)

      becomes:

          Map.new(enum, fn {k, v} -> {String.downcase(k), v} end)

      Stock Credo's `Refactor.MapInto` only catches `Enum.map |> Enum.into(%{})`.
      This check covers the direct `Enum.into(%{}, fn)` form.
      """
    ]

  @doc false
  def run(source_file, params \\ []) do
    issue_meta = IssueMeta.for(source_file, params)
    Credo.Code.prewalk(source_file, &traverse(&1, &2, issue_meta))
  end

  # Direct call form: Enum.into(enum, %{}, fn ...)
  defp traverse(
         {{:., _, [{:__aliases__, meta, [:Enum]}, :into]}, _,
          [_enum, {:%{}, _, []}, _fun]} = ast,
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
            {{:., _, [{:__aliases__, meta, [:Enum]}, :into]}, _,
             [{:%{}, _, []}, _fun]}
          ]} = ast,
         issues,
         issue_meta
       ) do
    {ast, issues ++ List.wrap(issue_for(issue_meta, meta[:line]))}
  end

  defp traverse(ast, issues, _issue_meta), do: {ast, issues}

  defp issue_for(issue_meta, line_no) do
    format_issue(issue_meta,
      message: "`Map.new/2` replaces `Enum.into(%{}, fn ...)`.",
      trigger: "Enum.into",
      line_no: line_no
    )
  end
end
