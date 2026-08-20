defmodule ForgeCredoChecks.TimingAndPrivateStateGuard do
  use Credo.Check,
    base_priority: :high,
    category: :warning,
    param_defaults: [excluded_paths: []],
    explanations: [
      check: """
      Wait on a signal, not a clock. Assert through the public API, not through
      a process's private state.

      ## Why

      `Process.sleep/1` (and `:timer.sleep/1`, the same function under another
      name) makes the test depend on scheduler timing. It is either
      too short (flaky on a loaded CI box) or too long (everyone pays the wall
      clock), and it never actually proves the awaited work finished — it only
      proves time passed.

      `:sys.get_state/1,2` reads a process's internal state, which is an
      implementation detail no caller is entitled to. It also does not
      synchronize anything: an independent sender, a timer, or an async task
      reply can still be in flight when it returns, so the read races the very
      work it is meant to observe. `:sys.replace_state/2` is worse — it fakes a
      state the real code paths can never produce, so the test passes on a
      state that cannot occur.

      ## Bad

          Process.sleep(200)
          assert :sys.get_state(pid).status == :ready

          :sys.replace_state(pid, fn state -> %{state | status: :ready} end)

      ## Good

          # Wait on a message the process actually sends.
          assert_receive {:worker_ready, ^pid}, 1_000

          # Wait on termination with a monitor.
          ref = Process.monitor(pid)
          assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 1_000

          # Or read state through a deliberately public, documented function
          # that is part of the module's real API.
          assert {:ok, :ready} = Worker.status(pid)

          # Reach the state under test by driving the public API that produces
          # it, rather than writing the state in directly.
          assert :ok = Worker.mark_ready(pid)

      Adding a test-only clause to production code — a
      `handle_call(:__test_state__, _, state)` that returns the whole state —
      is not an acceptable replacement. That is the same private-state read
      behind a new door, and it puts test scaffolding in the release. Expose a
      real, documented accessor for a value callers legitimately need, or
      assert on a message instead.

      ## What is flagged

      Call nodes for `Process.sleep/1`, `:timer.sleep/1`, `:sys.get_state/1,2`,
      and `:sys.replace_state/2`, including piped forms and the `apply/3` form
      (`apply(:sys, :get_state, [pid])`). Mentions that are not calls —
      strings, atoms, comments, and function captures like `&:sys.get_state/1`
      — are left alone.

      A test-only `GenServer.call(pid, :__test_state__)` is deliberately *not*
      detected: there is no reliable AST signature separating it from a genuine
      domain message, so any heuristic would both miss renamed variants and
      flag legitimate calls. It is ruled out in prose above instead.

      ## Configuration

      `excluded_paths` is a list of patterns (regexes or substrings) matched
      against each file's path; a matching file is skipped. Use it only as a
      shrinking migration bridge while moving callers onto signals and public
      APIs:

          {ForgeCredoChecks.TimingAndPrivateStateGuard,
           excluded_paths: [~r"^test/legacy_timing/"]}
      """,
      params: [
        excluded_paths: "Paths skipped entirely (regexes or substrings)."
      ]
    ]

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

  defp traverse(
         {{:., _dot_meta, [:sys, :get_state]}, meta, args} = ast,
         issues,
         issue_meta
       )
       when is_list(args) and length(args) in 0..2 do
    {ast, [issue_for(issue_meta, ":sys.get_state", meta) | issues]}
  end

  # `:timer.sleep/1` is `Process.sleep/1` under another name. Arity zero is the
  # piped form, where the duration sits outside the call node.
  defp traverse({{:., _dot_meta, [:timer, :sleep]}, meta, args} = ast, issues, issue_meta)
       when is_list(args) and length(args) in 0..1 do
    {ast, [issue_for(issue_meta, ":timer.sleep", meta) | issues]}
  end

  # `apply/3` reaches the same functions through a runtime dispatch, which the
  # remote-call clauses above cannot see.
  defp traverse({:apply, meta, [:sys, function, args]} = ast, issues, issue_meta)
       when function in [:get_state, :replace_state] and is_list(args) do
    {ast, [issue_for(issue_meta, ":sys.#{function}", meta) | issues]}
  end

  defp traverse({:apply, meta, [:timer, :sleep, args]} = ast, issues, issue_meta)
       when is_list(args) do
    {ast, [issue_for(issue_meta, ":timer.sleep", meta) | issues]}
  end

  defp traverse(
         {:apply, meta, [{:__aliases__, _alias_meta, [:Process]}, :sleep, args]} = ast,
         issues,
         issue_meta
       )
       when is_list(args) do
    {ast, [issue_for(issue_meta, "Process.sleep", meta) | issues]}
  end

  defp traverse(ast, issues, _issue_meta), do: {ast, issues}

  defp issue_for(issue_meta, trigger, meta) do
    format_issue(issue_meta,
      message: message_for(trigger),
      trigger: trigger,
      line_no: Keyword.get(meta, :line)
    )
  end

  defp message_for(trigger) when trigger in ["Process.sleep", ":timer.sleep"],
    do: sleep_message(trigger)

  defp message_for(trigger), do: private_state_message(trigger)

  defp sleep_message(trigger) do
    "`#{trigger}` makes this depend on scheduler timing rather than on the work finishing: " <>
      "it proves time passed, not that anything completed. Wait on a real signal instead — " <>
      "`assert_receive {:done, ...}` on a message the code actually sends, or " <>
      "`ref = Process.monitor(pid)` plus `assert_receive {:DOWN, ^ref, :process, _, _}` for " <>
      "termination. Use `:excluded_paths` only as a shrinking migration bridge."
  end

  defp private_state_message(trigger) do
    "`#{trigger}` reaches into a process's private state, which is not part of any contract " <>
      "and does not synchronize senders, timers, or async replies still in flight. Assert the " <>
      "observable outcome instead — `assert_receive` on a message the process really sends, " <>
      "`Process.monitor` plus `assert_receive {:DOWN, ...}` for termination, or a deliberately " <>
      "public, documented accessor on the module. Adding a test-only " <>
      "`handle_call(:__test_state__, _, state)` clause to production code is not an acceptable " <>
      "replacement: it is the same private read behind a new door. Use `:excluded_paths` only " <>
      "as a shrinking migration bridge."
  end
end
