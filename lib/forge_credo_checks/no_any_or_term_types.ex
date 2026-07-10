defmodule ForgeCredoChecks.NoAnyOrTermTypes do
  use Credo.Check,
    base_priority: :high,
    category: :warning,
    explanations: [
      check: """
      Do not use `any()` or `term()` in typespecs.

      ## Why

      `any()` and `term()` tell Dialyzer that every value is acceptable.
      That makes the spec look documented while removing much of the
      protection the spec was supposed to provide. Agents often reach for
      these broad types when they do not know the real shape yet.

      ## Bad

          @spec decode(binary()) :: term()
          @spec publish(any()) :: :ok | {:error, term()}
          @type payload :: %{optional(atom()) => any()}

      ## Good

          @type payload :: %{
                  required(:id) => String.t(),
                  optional(:metadata) => map()
                }

          @type publish_error :: :missing_topic | {:invalid_payload, payload()}

          @spec decode(binary()) :: {:ok, payload()} | {:error, :invalid_json}
          @spec publish(payload()) :: :ok | {:error, publish_error()}

      Use a named type, struct, tagged tuple, union, or a real type variable
      that preserves a relationship between input and output.
      """
    ]

  @spec_attributes [:spec, :callback, :macrocallback]
  @type_attributes [:type, :typep, :opaque]
  @banned_types [:any, :term]

  @doc false
  def run(source_file, params \\ []) do
    issue_meta = IssueMeta.for(source_file, params)
    Credo.Code.prewalk(source_file, &traverse(&1, &2, issue_meta))
  end

  defp traverse({:@, _meta, [{attribute, _attr_meta, [body]}]} = ast, issues, issue_meta)
       when attribute in @spec_attributes do
    new_issues =
      body
      |> spec_type_nodes()
      |> issues_in_type_nodes(issue_meta)

    {ast, issues ++ new_issues}
  end

  defp traverse({:@, _meta, [{attribute, _attr_meta, [body]}]} = ast, issues, issue_meta)
       when attribute in @type_attributes do
    new_issues =
      body
      |> type_definition_nodes()
      |> issues_in_type_nodes(issue_meta)

    {ast, issues ++ new_issues}
  end

  defp traverse(ast, issues, _issue_meta), do: {ast, issues}

  defp spec_type_nodes({:when, _meta, [spec, constraints]}) do
    spec_type_nodes(spec) ++ constraint_type_nodes(constraints)
  end

  defp spec_type_nodes({:"::", _meta, [head, return_type]}) do
    spec_head_type_nodes(head) ++ [return_type]
  end

  defp spec_type_nodes(_), do: []

  defp spec_head_type_nodes({_name, _meta, arg_types}) when is_list(arg_types), do: arg_types
  defp spec_head_type_nodes(_), do: []

  defp constraint_type_nodes(constraints) when is_list(constraints) do
    Enum.flat_map(constraints, fn
      {_type_variable, type} -> [type]
      _ -> []
    end)
  end

  defp constraint_type_nodes(_), do: []

  defp type_definition_nodes({:when, _meta, [definition, constraints]}) do
    type_definition_nodes(definition) ++ constraint_type_nodes(constraints)
  end

  defp type_definition_nodes({:"::", _meta, [_head, type]}), do: [type]
  defp type_definition_nodes(_), do: []

  defp issues_in_type_nodes(type_nodes, issue_meta) do
    {_type_nodes, issues} =
      Macro.prewalk(type_nodes, [], fn
        {type_name, meta, []} = ast, issues when type_name in @banned_types ->
          {ast, [issue_for(issue_meta, type_name, meta) | issues]}

        ast, issues ->
          {ast, issues}
      end)

    Enum.reverse(issues)
  end

  defp issue_for(issue_meta, type_name, meta) do
    trigger = "#{type_name}()"

    format_issue(issue_meta,
      message:
        "Avoid `#{trigger}` in typespecs; it accepts every value and weakens " <>
          "Dialyzer's protection. Replace it with a named type, struct, tagged " <>
          "tuple, union, or type variable that describes the real shape.",
      trigger: trigger,
      line_no: meta[:line],
      column: meta[:column]
    )
  end
end
