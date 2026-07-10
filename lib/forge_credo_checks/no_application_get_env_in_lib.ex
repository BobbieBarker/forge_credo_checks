defmodule ForgeCredoChecks.NoApplicationGetEnvInLib do
  use Credo.Check,
    base_priority: :high,
    category: :warning,
    param_defaults: [included_paths: [~r"^lib/"], allowed_paths: []],
    explanations: [
      check: """
      `Application.get_env/2,3` is a runtime config read. Inside `lib/` it is
      almost always the wrong reader: `get_env` silently returns `nil` (or a
      stale value) when the application environment is not yet loaded, so a
      compile-time configuration value is read as `nil` during releases and
      boot ordering races. Use `Application.compile_env/2,3` for values that
      are fixed at compile time, or `Application.fetch_env!/2` for values that
      are genuinely runtime-set and must fail loudly when missing.

      ## Why

      `compile_env` is evaluated when the module is compiled: the value is
      baked into the beam and is never re-read at runtime, so it cannot observe
      a half-loaded environment. `get_env`, by contrast, reads the live
      application environment every call. During a release boot the app env may
      not be loaded yet (or may carry a value from a previous boot phase),
      yielding `nil` or a stale value where a compile-time constant was
      intended. This class of bug is silent in `mix` and surfaces only in a
      packaged release.

      ## Bad

          # lib/my_app/config.ex
          def timeout, do: Application.get_env(:my_app, :timeout)

      ## Good

          # lib/my_app/config.ex
          def timeout, do: Application.compile_env(:my_app, :timeout)

      ## Configuration

      `included_paths` (default `[~r"^lib/"]`) lists path patterns (regexes or
      substrings) the check runs on; a file that matches none of them is
      skipped. `allowed_paths` (default `[]`) lists path patterns that are
      permitted to use `get_env` even within scope — use it for the rare
      `lib/` modules that legitimately read runtime config (a runtime-config
      registry, a hot-reload hook):

          {ForgeCredoChecks.NoApplicationGetEnvInLib,
           allowed_paths: [~r"^lib/my_app/runtime/"]}

      `Application.fetch_env/2` and `Application.fetch_env!/2` are deliberately
      out of scope for this check: they are the correct reader when a value is
      genuinely set at runtime and must fail loudly when absent. Only the
      silent `get_env` reader is flagged.
      """,
      params: [
        included_paths: "Paths (regexes or substrings) the check runs on (default: lib/).",
        allowed_paths: "In-scope paths permitted to use get_env (default: none)."
      ]
    ]

  @env_readers [:get_env]

  @doc false
  def run(source_file, params \\ []) do
    if in_scope?(source_file, params) do
      issue_meta = IssueMeta.for(source_file, params)
      Credo.Code.prewalk(source_file, &traverse(&1, &2, issue_meta))
    else
      []
    end
  end

  # A file is in scope when its path matches `included_paths` and does NOT match
  # `allowed_paths`. A non-binary filename (e.g. an in-memory "nofile") is out
  # of scope: there is no path to gate on, so the check does not fire.
  defp in_scope?(%{filename: filename}, params) when is_binary(filename) do
    included = params |> Params.get(:included_paths, __MODULE__) |> Enum.any?(&(filename =~ &1))
    allowed = params |> Params.get(:allowed_paths, __MODULE__) |> Enum.any?(&(filename =~ &1))
    included and not allowed
  end

  defp in_scope?(_source_file, _params), do: false

  defp traverse(
         {{:., _, [{:__aliases__, _, [:Application]}, fun]}, meta, args} = ast,
         issues,
         issue_meta
       )
       when fun in @env_readers and is_list(args) do
    {ast, [issue_for(issue_meta, fun, meta) | issues]}
  end

  defp traverse(ast, issues, _issue_meta), do: {ast, issues}

  defp issue_for(issue_meta, fun, meta) do
    format_issue(issue_meta,
      message:
        "`Application.#{fun}` is a runtime config read that silently returns `nil` or a " <>
          "stale value when the app env is not yet loaded. Use `Application.compile_env/2,3` " <>
          "for compile-time values, or `Application.fetch_env!/2` for runtime-set values that " <>
          "must fail loudly when missing.",
      trigger: "Application.#{fun}",
      line_no: Keyword.get(meta, :line)
    )
  end
end
