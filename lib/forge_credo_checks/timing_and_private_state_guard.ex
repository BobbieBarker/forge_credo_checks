defmodule ForgeCredoChecks.TimingAndPrivateStateGuard do
  @moduledoc """
  Flags timing sleeps and private GenServer state mutation in tests and checks.
  """

  use Credo.Check,
    base_priority: :high,
    category: :warning,
    param_defaults: [excluded_paths: []],
    explanations: [
      check: """
      Timing sleeps and private process-state mutation hide the real contract.

      ## Why

      `Process.sleep/1` makes tests depend on scheduler timing instead of a
      deterministic signal. `:sys.replace_state/2` reaches into a process and
      mutates implementation details rather than exercising the public API.

      Use behavioural contract coverage instead. The reference pattern for the
      Forge/Anubis migration lives in `contracts/template_variables_contract_test.exs`.

      ## What is flagged

      This check flags actual remote call nodes for `Process.sleep/1` and
      `:sys.replace_state/2`. String literals, atom literals, and function
      captures that merely mention those names are not flagged.

      ## Configuration

      `excluded_paths` is a list of patterns (regexes or substrings) matched
      against each file's path; a matching file is skipped. Use it only as a
      shrinking migration bridge while moving callers to contract tests:

          {ForgeCredoChecks.TimingAndPrivateStateGuard,
           excluded_paths: [~r"^test/legacy_timing/"]}
      """,
      params: [
        excluded_paths: "Paths skipped entirely (regexes or substrings)."
      ]
    ]

  @contract_path "contracts/template_variables_contract_test.exs"

  @doc false
  def run(source_file, params \\ []) do
    if excluded_path?(source_file, params) do
      []
    else
      issue_meta = IssueMeta.for(source_file, params)
      Credo.Code.prewalk(source_file, &traverse(&1, &2, issue_meta))
    end
  end

  defp excluded_path?(%{filename: filename}, params) when is_binary(filename) do
    params
    |> Params.get(:excluded_paths, __MODULE__)
    |> Enum.any?(&(filename =~ &1))
  end

  defp excluded_path?(_source_file, _params), do: false

  defp traverse(
         {:&, amp_meta,
          [{:/, slash_meta, [{{:., _dot_meta, [_mod, _fun]}, _call_meta, []}, arity]}]},
         issues,
         _issue_meta
       )
       when is_integer(arity) do
    {{:&, amp_meta, [{:/, slash_meta, [:__captured_timing_private_state_guard__, arity]}]},
     issues}
  end

  defp traverse(
         {{:., _dot_meta, [{:__aliases__, _alias_meta, [:Process]}, :sleep]}, meta, [_duration]} =
           ast,
         issues,
         issue_meta
       ) do
    {ast, [issue_for(issue_meta, "Process.sleep", meta) | issues]}
  end

  defp traverse(
         {{:., _dot_meta, [:sys, :replace_state]}, meta, [_pid, _fun]} = ast,
         issues,
         issue_meta
       ) do
    {ast, [issue_for(issue_meta, ":sys.replace_state", meta) | issues]}
  end

  defp traverse(ast, issues, _issue_meta), do: {ast, issues}

  defp issue_for(issue_meta, trigger, meta) do
    format_issue(issue_meta,
      message:
        "`#{trigger}` bypasses the public contract. Replace timing/private-state " <>
          "assertions with behavioural coverage in `#{@contract_path}`; string " <>
          "and atom mentions are allowed, but call nodes are not. Use " <>
          "`:excluded_paths` only as a shrinking migration bridge.",
      trigger: trigger,
      line_no: Keyword.get(meta, :line)
    )
  end
end
