defmodule ForgeCredoChecks.ChainedMapGet do
  use Credo.Check,
    base_priority: :higher,
    category: :refactor,
    explanations: [
      check: """
      Replace `Map.get(a, key) || Map.get(b, key)` with boundary normalization.

      ## Why

      Chained `Map.get/2` calls are a stronger signal than a local default:
      the caller does not know which input shape it has. Each call site that
      fishes across multiple maps or key spellings makes the data contract
      harder to see and easier to drift.

      ## How to fix

          # BEFORE
          Map.get(context, :issue) || Map.get(arguments, :issue)

          # AFTER
          normalized = normalize_issue_input(context, arguments)
          normalized.issue

      Normalize once at the ingestion boundary, then consume a single known
      shape in the rest of the code.

      ## What NOT to do

      Do not add more `|| Map.get(...)` fallbacks locally. That spreads the
      schema ambiguity instead of removing it.
      """
    ]

  @doc false
  def run(source_file, params \\ []) do
    issue_meta = IssueMeta.for(source_file, params)
    Credo.Code.prewalk(source_file, &traverse(&1, &2, issue_meta))
  end

  defp traverse({:||, meta, [left, right]} = ast, issues, issue_meta) do
    if map_get_2?(left) and map_get_2?(right) do
      {ast, [issue_for(issue_meta, meta[:line]) | issues]}
    else
      {ast, issues}
    end
  end

  defp traverse(ast, issues, _issue_meta), do: {ast, issues}

  defp map_get_2?({{:., _, [{:__aliases__, _, [:Map]}, :get]}, _, [_map, _key]}), do: true

  defp map_get_2?(
         {:|>, _,
          [
            _map,
            {{:., _, [{:__aliases__, _, [:Map]}, :get]}, _, [_key]}
          ]}
       ),
       do: true

  defp map_get_2?(_), do: false

  defp issue_for(issue_meta, line_no) do
    format_issue(issue_meta,
      message: "Normalize the input shape at the boundary; do not fish across multiple sources.",
      trigger: "||",
      line_no: line_no
    )
  end
end
