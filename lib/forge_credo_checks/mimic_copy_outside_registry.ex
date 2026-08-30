defmodule ForgeCredoChecks.MimicCopyOutsideRegistry do
  use Credo.Check,
    base_priority: :high,
    category: :warning,
    param_defaults: [
      included_paths: [~r"^test/"],
      registration_paths: [~r"^test/test_helper\.exs$"],
      registry: "ForgeSymphony.MockingGuide.mimic_modules/0"
    ],
    explanations: [
      check: """
      `Mimic.copy/1` belongs in the suite's single registration point, not in a
      test file.

      ## Why

      A per-file copy is not a local decision. `Mimic.copy/1` marks the module
      VM-globally in `Mimic.Server` and registers an `ExUnit.after_suite/1`
      callback, so one call changes how the module behaves for the whole run and
      leaves a suite-wide hook behind.

      It also copies a module without adding it to the registry the suite reads.
      The "never Mimic a module that has a Mox mock" invariant is enforced by
      intersecting that registry against the Mox one, so a module copied outside
      it is outside the invariant: it can be Mimicked and Mox-mocked at once and
      nothing fails. The registry is the only place that intersection can see.

      Register the module instead. There is no case where a file needs a copy the
      registry should not know about.

      ## Bad

          defmodule MyTest do
            use ExUnit.Case
            Mimic.copy(SomeModule)
          end

          defmodule MyOtherTest do
            use Mimic          # imports copy/1
            copy(SomeModule)
          end

      ## Good

          # test/test_helper.exs
          Enum.each(MyApp.MockingGuide.mimic_modules(), &Mimic.copy/1)

      ## What is flagged

      Within `included_paths` and outside `registration_paths`: a `Mimic.copy`
      call or capture, and a bare `copy` call or capture in a file that `use`s or
      `import`s `Mimic`, which is how the module prefix disappears.

      Prose is not flagged. The check reads the AST, so naming `Mimic.copy/1` in
      a `@moduledoc`, `@doc` or comment is left alone.
      """,
      params: [
        included_paths: "Paths (regexes or substrings) the check runs on.",
        registration_paths: "Paths permitted to call it: the suite's registration point.",
        registry: "The registry named in the issue message as the place to register instead."
      ]
    ]

  @doc false
  def run(source_file, params \\ []) do
    if checked_file?(source_file, params) do
      source_file |> collect() |> issues_for(IssueMeta.for(source_file, params))
    else
      []
    end
  end

  # One traversal collects everything. Whether the file imports Mimic decides
  # only whether a bare `copy` counts, and that is resolved after the walk rather
  # than by walking a second time to answer it first.
  defp collect(source_file) do
    Credo.Code.prewalk(source_file, &traverse/2, %{qualified: [], bare: [], imported?: false})
  end

  defp issues_for(%{qualified: qualified, bare: bare, imported?: imported?}, issue_meta) do
    bare = if imported?, do: bare, else: []

    (qualified ++ bare)
    |> Enum.sort()
    |> Enum.map(fn {line_no, trigger} -> issue_for(issue_meta, line_no, trigger) end)
  end

  defp checked_file?(%{filename: filename}, params) when is_binary(filename) do
    included?(filename, params, :included_paths) and
      not included?(filename, params, :registration_paths)
  end

  defp checked_file?(_source_file, _params), do: false

  defp included?(filename, params, key) do
    params
    |> Params.get(key, __MODULE__)
    |> Enum.any?(&(filename =~ &1))
  end

  # `use Mimic` expands to `import Mimic`, so both spellings put a bare `copy/1`
  # in scope and both have to count.
  defp traverse({directive, _meta, [{:__aliases__, _, [:Mimic]} | _]} = ast, acc)
       when directive in [:use, :import] do
    {ast, %{acc | imported?: true}}
  end

  # `Mimic.copy(Mod)` and, inside `&Mimic.copy/1`, the same dotted node.
  defp traverse({{:., _, [{:__aliases__, _, [:Mimic]}, :copy]}, meta, _args} = ast, acc) do
    {ast, %{acc | qualified: [{line(meta), "Mimic.copy"} | acc.qualified]}}
  end

  # A bare `copy(Mod)` whose scope is decided after the walk.
  defp traverse({:copy, meta, args} = ast, acc) when is_list(args) do
    {ast, %{acc | bare: [{line(meta), "copy"} | acc.bare]}}
  end

  # A bare `&copy/1` capture in that same scope.
  defp traverse({:/, meta, [{:copy, _, nil}, 1]} = ast, acc) do
    {ast, %{acc | bare: [{line(meta), "copy"} | acc.bare]}}
  end

  defp traverse(ast, acc), do: {ast, acc}

  defp line(meta), do: Keyword.get(meta, :line)

  defp issue_for(issue_meta, line_no, trigger) do
    format_issue(issue_meta,
      message:
        "`#{trigger}` outside the suite's registration point copies a module the mocking " <>
          "registry never sees, which puts it outside the Mox/Mimic coexistence check and " <>
          "leaves a VM-global mark plus an after_suite hook behind. Register it in " <>
          "#{registry_name(issue_meta)} instead.",
      trigger: trigger,
      line_no: line_no
    )
  end

  defp registry_name(issue_meta) do
    issue_meta
    |> IssueMeta.params()
    |> Params.get(:registry, __MODULE__)
  end
end
