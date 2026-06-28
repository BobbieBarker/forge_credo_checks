defmodule ForgeCredoChecks.LargeStruct do
  use Credo.Check,
    base_priority: :high,
    category: :warning,
    param_defaults: [max_fields: 32],
    explanations: [
      check: """
      A struct with 32 or more fields loses the BEAM's flat-map optimization.

      ## Why

      The runtime stores a map with at most 32 keys as a "flat map": a shared
      sorted key tuple plus a compact value array, with cheap lookups and
      updates. At 32 keys and above the map becomes a hashmap (a HAMT), which
      uses more memory per instance and turns those cheap operations into tree
      traversals. A struct is a map, so a struct this wide pays the cost on
      every instance, often across many in flight at once.

      A struct that has grown past this point is usually carrying several
      unrelated concerns that want to be separate, nested structs.

      ## Bad

          # 33 fields, all on one struct
          defstruct [:f1, :f2, :f3, :f4, :f5, :f6, :f7, :f8, :f9, :f10, :f11]

      ## Good

          # grouped into focused sub-structs
          defstruct [:identity, :config, :working_state]

      ## Configuration

      `max_fields` (default 32) is the field count at which the check fires.
      """
    ]

  @doc false
  def run(source_file, params \\ []) do
    issue_meta = IssueMeta.for(source_file, params)
    max_fields = Params.get(params, :max_fields, __MODULE__)
    Credo.Code.prewalk(source_file, &traverse(&1, &2, issue_meta, max_fields))
  end

  defp traverse({:defstruct, meta, [fields]} = ast, issues, issue_meta, max_fields)
       when is_list(fields) do
    count = length(fields)

    if count >= max_fields do
      {ast, [issue_for(issue_meta, count, max_fields, meta) | issues]}
    else
      {ast, issues}
    end
  end

  defp traverse(ast, issues, _issue_meta, _max_fields), do: {ast, issues}

  defp issue_for(issue_meta, count, max_fields, meta) do
    format_issue(issue_meta,
      message: """
      Struct defines #{count} fields (limit #{max_fields}). A map with 32 or more keys \
      drops the BEAM flat-map representation and costs more per instance; split the \
      struct into grouped, nested structs.\
      """,
      trigger: "defstruct",
      line_no: Keyword.get(meta, :line)
    )
  end
end
