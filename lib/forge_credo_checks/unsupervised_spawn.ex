defmodule ForgeCredoChecks.UnsupervisedSpawn do
  use Credo.Check,
    base_priority: :high,
    category: :warning,
    param_defaults: [excluded_paths: []],
    explanations: [
      check: """
      Long-lived processes belong under a supervisor, not a raw spawn.

      ## Why

      `spawn/1,3`, `spawn_link/1,3`, `spawn_monitor/1,3`, and `Process.spawn`
      start a process with no supervisor: nothing restarts it after a crash,
      its start and shutdown ordering relative to the rest of the tree is
      undefined, and it is invisible to supervision-tree introspection. A
      crash becomes permanent absence rather than a restart.

      Start fixed processes as supervisor children and runtime-created ones
      under a `DynamicSupervisor`. For fire-and-forget work use
      `Task.Supervisor.start_child/2`; for awaited work use
      `Task.Supervisor.async_nolink/3`.

      ## Bad

          spawn(fn -> do_work() end)
          spawn_link(MyMod, :loop, [state])

      ## Good

          Task.Supervisor.start_child(MyApp.TaskSupervisor, fn -> do_work() end)
          DynamicSupervisor.start_child(MyApp.Sup, {MyWorker, arg})

      ## Configuration

      `excluded_paths` is a list of patterns (regexes or substrings) matched
      against each file's path; a file that matches is skipped. Use it where a
      different convention legitimately applies, such as test files that create
      unsupervised processes on purpose (an orphan-reaping test cannot use a
      supervised process):

          {ForgeCredoChecks.UnsupervisedSpawn, excluded_paths: [~r/_test\\.exs$/]}
      """
    ]

  @raw_spawns [:spawn, :spawn_link, :spawn_monitor]

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

  # Kernel spawn / spawn_link / spawn_monitor called as a local function
  defp traverse({name, meta, args} = ast, issues, issue_meta)
       when name in @raw_spawns and is_list(args) do
    {ast, [issue_for(issue_meta, name, meta) | issues]}
  end

  # Process.spawn(...)
  defp traverse(
         {{:., _, [{:__aliases__, _, [:Process]}, :spawn]}, meta, args} = ast,
         issues,
         issue_meta
       )
       when is_list(args) do
    {ast, [issue_for(issue_meta, "Process.spawn", meta) | issues]}
  end

  # :erlang.spawn / spawn_link / spawn_monitor
  defp traverse({{:., _, [:erlang, name]}, meta, args} = ast, issues, issue_meta)
       when name in @raw_spawns and is_list(args) do
    {ast, [issue_for(issue_meta, "erlang.#{name}", meta) | issues]}
  end

  defp traverse(ast, issues, _issue_meta), do: {ast, issues}

  defp issue_for(issue_meta, name, meta) do
    format_issue(issue_meta,
      message: """
      `#{name}` starts an unsupervised process: nothing restarts it on crash and it is \
      invisible to the supervision tree. Start it under a supervisor, a `DynamicSupervisor`, \
      or `Task.Supervisor` instead.\
      """,
      trigger: to_string(name),
      line_no: Keyword.get(meta, :line)
    )
  end
end
