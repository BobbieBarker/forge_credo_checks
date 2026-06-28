defmodule ForgeCredoChecks.MapGetWithOr do
  use Credo.Check,
    base_priority: :high,
    category: :refactor,
    explanations: [
      check: """
      Replace `Map.get(map, key) || fallback` with `Map.get/3` or boundary normalization.

      ## Why

      `Map.get/2 || fallback` silently treats `false` as missing data and
      encourages call sites to fish through input shapes instead of defining
      one shape at the boundary. LLMs frequently produce this when they are
      unsure whether a value lives under one key, another key, or another map.

      ## How to fix

          # BEFORE
          Map.get(opts, :retries) || 0

          # AFTER
          Map.get(opts, :retries, 0)

      If the fallback is another source, normalize the input once at the
      ingestion boundary and read the normalized key locally.

      ## What NOT to do

      Do not chain `Map.get/2` calls with `||` to support several possible
      input shapes. That hides schema drift and turns every consumer into a
      partial data-normalization layer.
      """
    ]

  @doc false
  def run(source_file, params \\ []) do
    issue_meta = IssueMeta.for(source_file, params)
    Credo.Code.prewalk(source_file, &traverse(&1, &2, issue_meta))
  end

  defp traverse({:||, meta, [left, _right]} = ast, issues, issue_meta) do
    if map_get_2?(left) do
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
      message: "Use Map.get/3 for defaults, or normalize the data at its ingestion boundary.",
      trigger: "||",
      line_no: line_no
    )
  end
end
