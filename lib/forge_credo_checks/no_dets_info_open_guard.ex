defmodule ForgeCredoChecks.NoDetsInfoOpenGuard do
  @moduledoc """
  Rejects gating `:dets.open_file/2` on a stale `:dets.info/1` registry read.

  ## Why

  A caller that short-circuits `open_file` because `:dets.info/1` reports the
  table is already open never becomes a registered `dets_server` user. Data ops
  still work while the registering process lives, but when that process closes
  the table, `dets_server`'s `handle_close/4` deletes the registry row
  synchronously and the unregistered caller's next write raises.

  The correct pattern is to call `:dets.open_file/2` unconditionally and match
  `{:error, {:already_started, _}}`, which registers every caller.

  ## Flagged

  Any arity-1 `:dets.info(table)` compared against `:undefined` inside a lib
  source file, e.g.:

      if :dets.info(table) !== :undefined do
        {:ok, table}
      else
        :dets.open_file(table, ...)
      end

      case :dets.info(table) do
        :undefined -> :dets.open_file(table, ...)
        _ -> {:ok, table}
      end

  ## Not flagged

  - `:dets.info(table, :size)` and other arity-2 calls (legitimate size/metadata
    queries that do not gate `open_file`).
  - Calls in test files (the guard is a production-only hazard).

  ## How to fix

  Replace the guarded branch with an unconditional `:dets.open_file/2` that
  matches `{:error, {:already_started, ^table}}` as success.
  """

  use Credo.Check,
    base_priority: :high,
    category: :warning,
    explanations: [
      check: """
      Do not gate :dets.open_file/2 on :dets.info/1. The info read does not
      register the caller as a dets_server user, so a sibling close deletes
      the registry row and the caller's next write raises. Call open_file
      unconditionally and match {:already_started, _} instead.
      """
    ]

  alias Credo.{Code, IssueMeta}

  @comparison_ops [:===, :!==, :==, :!=]

  @doc false
  @spec run(Credo.SourceFile.t(), keyword()) :: [Credo.Issue.t()]
  def run(%{filename: filename} = source_file, params \\ []) do
    if lib_file?(filename) do
      issue_meta = IssueMeta.for(source_file, params)
      Code.prewalk(source_file, &traverse(&1, &2, issue_meta))
    else
      []
    end
  end

  defp lib_file?(filename) when is_binary(filename) do
    filename
    |> Path.split()
    |> Enum.any?(&(&1 === "lib"))
  end

  defp lib_file?(_filename), do: false

  defp traverse({:case, meta, [subject, [do: clauses]]} = ast, issues, issue_meta) do
    if arity1_dets_info?(subject) and case_matches_undefined?(clauses) do
      {ast, [issue_for(issue_meta, ":dets.info/1", Keyword.get(meta, :line)) | issues]}
    else
      {ast, issues}
    end
  end

  defp traverse({op, meta, [left, right]} = ast, issues, issue_meta)
       when op in @comparison_ops do
    if open_guard?(left, right) or open_guard?(right, left) do
      {ast, [issue_for(issue_meta, ":dets.info/1", Keyword.get(meta, :line)) | issues]}
    else
      {ast, issues}
    end
  end

  defp traverse(ast, issues, _issue_meta), do: {ast, issues}

  defp open_guard?(info_side, other_side) do
    arity1_dets_info?(info_side) and undefined_literal?(other_side)
  end

  defp case_matches_undefined?(clauses) do
    Enum.any?(clauses, &undefined_case_clause?/1)
  end

  defp undefined_case_clause?({:->, _meta, [patterns, _body]}) when is_list(patterns) do
    Enum.any?(patterns, &undefined_case_pattern?/1)
  end

  defp undefined_case_clause?(_clause), do: false

  defp undefined_case_pattern?({:when, _meta, [pattern | _guards]}),
    do: undefined_case_pattern?(pattern)

  defp undefined_case_pattern?(pattern), do: undefined_literal?(pattern)

  defp arity1_dets_info?({{:., _dot_meta, [:dets, :info]}, _call_meta, [_arg]}), do: true
  defp arity1_dets_info?(_other), do: false

  defp undefined_literal?(:undefined), do: true
  defp undefined_literal?(_other), do: false

  defp issue_for(issue_meta, trigger, line_no) do
    format_issue(issue_meta,
      message: """
      :dets.info/1 used as an open-file guard does not register the caller as a \
      dets_server user. Call :dets.open_file/2 unconditionally and match \
      {:already_started, _} instead.
      """,
      trigger: trigger,
      line_no: line_no
    )
  end
end
