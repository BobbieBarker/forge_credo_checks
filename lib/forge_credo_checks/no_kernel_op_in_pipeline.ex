defmodule ForgeCredoChecks.NoKernelOpInPipeline do
  use Credo.Check,
    base_priority: :high,
    category: :refactor,
    explanations: [
      check: """
      Don't pipe into `Kernel.<op>/2` — use the operator in infix position.

      ## Why

      LLMs produce code like `list |> Enum.sort() |> Kernel.==(other)` because
      they try to keep everything in one pipeline. In Elixir, comparison and
      boolean operators are infix; a qualified `Kernel.==/2` call in a pipe
      reads as a function the LLM hallucinated, not a comparison.

      Arithmetic operators (`+`, `-`, `*`, `/`) are NOT flagged — they have
      legitimate uses inside pipelines and the alternative is no clearer.

      ## Bad

          list |> Enum.uniq() |> Enum.sort() |> Kernel.==(other)

          score |> calculate() |> Kernel.>=(threshold)

      ## Good

          # one-step pipe → infix
          list |> Enum.sort() == other

          # zero-step → just the comparison
          calculate(score) >= threshold

          # multi-step → parenthesize the pipeline
          (list |> Enum.uniq() |> Enum.sort()) == other

      ## Operators flagged

      `==`, `!=`, `===`, `!==`, `<`, `>`, `<=`, `>=`, `and`, `or`.
      """
    ]

  @flagged_ops ~w(== != === !== < > <= >= and or)a

  @doc false
  def run(source_file, params \\ []) do
    issue_meta = IssueMeta.for(source_file, params)
    Credo.Code.prewalk(source_file, &traverse(&1, &2, issue_meta))
  end

  defp traverse(
         {:|>, _, [_lhs, {{:., _, [{:__aliases__, _, [:Kernel]}, op]}, meta, [_arg]}]} = ast,
         issues,
         issue_meta
       )
       when op in @flagged_ops do
    issue =
      format_issue(issue_meta,
        message:
          "Piping into `Kernel.#{op}/2` is non-idiomatic. Use the operator in infix " <>
            "position: `(pipeline) #{op} value` (or extract the pipeline to a variable first).",
        trigger: "Kernel.#{op}",
        line_no: Keyword.get(meta, :line)
      )

    {ast, [issue | issues]}
  end

  defp traverse(ast, issues, _issue_meta), do: {ast, issues}
end
