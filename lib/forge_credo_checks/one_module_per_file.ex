defmodule ForgeCredoChecks.OneModulePerFile do
  use Credo.Check,
    base_priority: :normal,
    category: :design,
    param_defaults: [excluded_paths: [~r{(^|[\\/])test[\\/]}, ~r"_test\.exs$"]],
    explanations: [
      check: """
      Define at most one module in each source file.

      ## Why

      A one-module-per-file layout makes a module's source location predictable,
      keeps ownership boundaries visible, and prevents unrelated modules from
      accumulating behind a filename that describes only the first one. Nested
      `defmodule` declarations count too: a nested name still defines a separate
      module and should live in its own file.

      ## Bad

          defmodule MyApp.Parser do
          end

          defmodule MyApp.Formatter do
          end

      ## Good

          # lib/my_app/parser.ex
          defmodule MyApp.Parser do
          end

          # lib/my_app/formatter.ex
          defmodule MyApp.Formatter do
          end

      ## Configuration

      `excluded_paths` lists path patterns (regexes or substrings) that the check
      skips. By default, files under a `test/` directory and files ending in
      `_test.exs` are excluded because tests sometimes need a small nested module
      as a fixture. Set `excluded_paths: []` to enforce the rule in tests too, or
      replace the defaults with project-specific exclusions.

      The check counts literal `defmodule` declarations, including nested and
      reopened modules. A `defmodule` inside `quote` is ignored because it is AST
      emitted by a macro rather than a module defined by the source file itself.
      `defprotocol` and `defimpl` are separate constructs and are outside this
      check's scope.
      """,
      params: [
        excluded_paths:
          "Paths skipped entirely (default: test/ directories and *_test.exs files)."
      ]
    ]

  @doc false
  @impl true
  @spec run(Credo.SourceFile.t(), Keyword.t()) :: [Credo.Issue.t()]
  def run(source_file, params \\ []) do
    if excluded_path?(source_file, params) do
      []
    else
      issue_meta = IssueMeta.for(source_file, params)

      {_module_count, issues} =
        Credo.Code.prewalk(source_file, &traverse(&1, &2, issue_meta), {0, []})

      Enum.reverse(issues)
    end
  end

  defp excluded_path?(%{filename: filename}, params) when is_binary(filename) do
    params
    |> Params.get(:excluded_paths, __MODULE__)
    |> Enum.any?(&(filename =~ &1))
  end

  defp excluded_path?(_source_file, _params), do: false

  # Quoted module declarations are data emitted by a macro, not modules defined
  # by this source file. Replacing the quote node prunes its children from the
  # prewalk; only the accumulator matters to this check.
  defp traverse({:quote, _meta, [_ | _]}, state, _issue_meta), do: {nil, state}

  defp traverse({:defmodule, _meta, [_module_ast, _body]} = ast, {0, issues}, _issue_meta) do
    {ast, {1, issues}}
  end

  defp traverse(
         {:defmodule, meta, [module_ast, _body]} = ast,
         {module_count, issues},
         issue_meta
       ) do
    module_name = Macro.to_string(module_ast)
    issue = issue_for(issue_meta, module_name, meta)

    {ast, {module_count + 1, [issue | issues]}}
  end

  defp traverse(ast, state, _issue_meta), do: {ast, state}

  defp issue_for(issue_meta, module_name, meta) do
    format_issue(issue_meta,
      message:
        "`#{module_name}` is an additional module in this file. Move it into its own file " <>
          "so each source file defines at most one module.",
      trigger: module_name,
      line_no: Keyword.get(meta, :line)
    )
  end
end
