defmodule ForgeCredoChecks.NoSourceInspectionInTest do
  use Credo.Check,
    base_priority: :high,
    category: :warning,
    param_defaults: [included_paths: [~r"_test\.exs$"]],
    explanations: [
      check: """
      Tests must exercise behaviour through the public API, not inspect the TEXT
      of production source files.

      ## Why

      A "contract test" that `File.read!`s a `lib/*.ex` module and asserts on its
      source with `=~` / `Regex` / `Code.string_to_quoted` is brittle. It breaks
      on behaviour-preserving refactors (a `case` becoming multi-clause function
      heads, a formatter reflow, a rename) even though the runtime behaviour is
      unchanged, and it gives false confidence: a matched substring may be a
      comment or a shadowed clause, and a passing grep never actually ran the
      code. AST inspection of the same source (`Code.string_to_quoted` +
      `Macro` walking) has the same fault: it asserts on structure, not behaviour.

      Test the real contract instead. Call the producer to get each output shape,
      call the consumer with each shape, and assert the returned value or effect.
      If the code under test is private, make it public (a `@doc false` function
      is fine) or extract a reactor closure into a named public function.
      Exposing a function to test critical behaviour is always preferable to
      asserting on source text.

      ## Bad

          @impl_source "lib/forge_symphony/.../implementation.ex"
          source = File.read!(@impl_source)
          assert source =~ "%StepFailure{}"

      ## Good

          assert {:ok, %{status: :failed, error: :boom}} =
                   Implementation.validate_dispatch_result(%StepFailure{error: :boom}, ...)

      ## Configuration

      `included_paths` (default `[~r"_test\\.exs$"]`) scopes the check to test
      files. Within those, it flags a string literal under a `lib/` path ending
      in `.ex`/`.exs` when used as a module-attribute value or as an argument to
      `File.read!` / `File.read` / `Code.string_to_quoted` /
      `Code.string_to_quoted!`. Reading generated or fixture files (paths that do
      not point at `lib/*.ex`) is not flagged.
      """,
      params: [
        included_paths: "Paths (regexes or substrings) the check runs on (default: *_test.exs)."
      ]
    ]

  @lib_source_pattern ~r{(^|/)lib/.+\.exs?$}
  @readers [:read!, :read]
  @quoters [:string_to_quoted, :string_to_quoted!]

  @doc false
  def run(source_file, params \\ []) do
    if test_file?(source_file, params) do
      issue_meta = IssueMeta.for(source_file, params)
      Credo.Code.prewalk(source_file, &traverse(&1, &2, issue_meta))
    else
      []
    end
  end

  defp test_file?(%{filename: filename}, params) when is_binary(filename) do
    params
    |> Params.get(:included_paths, __MODULE__)
    |> Enum.any?(&(filename =~ &1))
  end

  defp test_file?(_source_file, _params), do: false

  # A module attribute assigned a lib source path: `@impl_source "lib/.../x.ex"`.
  defp traverse({:@, meta, [{name, _, [arg]}]} = ast, issues, issue_meta)
       when is_atom(name) and is_binary(arg) do
    flag_if_lib(ast, issues, issue_meta, meta, "@#{name}", arg)
  end

  # `File.read!("lib/.../x.ex")` / `File.read(...)`.
  defp traverse(
         {{:., _, [{:__aliases__, _, [:File]}, reader]}, meta, [arg | _]} = ast,
         issues,
         issue_meta
       )
       when reader in @readers and is_binary(arg) do
    flag_if_lib(ast, issues, issue_meta, meta, "File.#{reader}", arg)
  end

  # `Code.string_to_quoted("lib/.../x.ex")` / `Code.string_to_quoted!(...)`.
  defp traverse(
         {{:., _, [{:__aliases__, _, [:Code]}, quoter]}, meta, [arg | _]} = ast,
         issues,
         issue_meta
       )
       when quoter in @quoters and is_binary(arg) do
    flag_if_lib(ast, issues, issue_meta, meta, "Code.#{quoter}", arg)
  end

  defp traverse(ast, issues, _issue_meta), do: {ast, issues}

  defp flag_if_lib(ast, issues, issue_meta, meta, trigger, arg) do
    if arg =~ @lib_source_pattern do
      {ast, [issue_for(issue_meta, meta, trigger) | issues]}
    else
      {ast, issues}
    end
  end

  defp issue_for(issue_meta, meta, trigger) do
    format_issue(issue_meta,
      message:
        "`#{trigger}` reads production source in a test. Verify behaviour by calling the real " <>
          "function (make it public if needed), not by inspecting source text.",
      trigger: trigger,
      line_no: Keyword.get(meta, :line)
    )
  end
end
