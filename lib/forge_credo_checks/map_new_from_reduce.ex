defmodule ForgeCredoChecks.MapNewFromReduce do
  use Credo.Check,
    base_priority: :high,
    category: :refactor,
    explanations: [
      check: """
      `Map.new/2` replaces a hand-rolled `Enum.reduce(_, %{}, fn _, acc ->
      Map.put(acc, k, v) end)` with the idiomatic key-value tuple form.

      This:

          Enum.reduce(things, %{}, fn x, acc ->
            Map.put(acc, x.id, transform(x))
          end)

      becomes:

          Map.new(things, fn x -> {x.id, transform(x)} end)

      The reduce form obscures intent (build a map keyed by something) and
      is a common LLM trap when rewriting Python dict-comprehension code
      into Elixir.
      """
    ]

  @doc false
  def run(source_file, params \\ []) do
    issue_meta = IssueMeta.for(source_file, params)
    Credo.Code.prewalk(source_file, &traverse(&1, &2, issue_meta))
  end

  # Direct call: Enum.reduce(enum, %{}, fn x, acc -> Map.put(acc, k, v) end)
  defp traverse(
         {{:., _, [{:__aliases__, meta, [:Enum]}, :reduce]}, _,
          [_enum, {:%{}, _, []}, fun]} = ast,
         issues,
         issue_meta
       ) do
    {ast, maybe_report(fun, issues, issue_meta, meta[:line])}
  end

  # Piped form: enum |> Enum.reduce(%{}, fn x, acc -> Map.put(acc, k, v) end)
  defp traverse(
         {:|>, _,
          [
            _,
            {{:., _, [{:__aliases__, meta, [:Enum]}, :reduce]}, _,
             [{:%{}, _, []}, fun]}
          ]} = ast,
         issues,
         issue_meta
       ) do
    {ast, maybe_report(fun, issues, issue_meta, meta[:line])}
  end

  defp traverse(ast, issues, _issue_meta), do: {ast, issues}

  # The fn must be exactly `fn _x, acc -> Map.put(acc, _, _) end` where
  # the acc binding name matches the first arg of Map.put.
  defp maybe_report(
         {:fn, _,
          [
            {:->, _,
             [
               [_first_arg, {acc_name, _, acc_ctx}],
               {{:., _, [{:__aliases__, _, [:Map]}, :put]}, _,
                [{acc_name, _, put_ctx}, _key, _value]}
             ]}
          ]},
         issues,
         issue_meta,
         line_no
       )
       when is_atom(acc_name) and acc_name != :_ and is_atom(acc_ctx) and is_atom(put_ctx) do
    issues ++ List.wrap(issue_for(issue_meta, line_no))
  end

  defp maybe_report(_fun, issues, _issue_meta, _line_no), do: issues

  defp issue_for(issue_meta, line_no) do
    format_issue(issue_meta,
      message: "`Map.new/2` replaces `Enum.reduce(_, %{}, &Map.put(acc, k, v))`.",
      trigger: "Enum.reduce",
      line_no: line_no
    )
  end
end
