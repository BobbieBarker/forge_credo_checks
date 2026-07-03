defmodule ForgeCredoChecks.NoSourceInspectionInTest do
  use Credo.Check,
    base_priority: :high,
    category: :warning,
    param_defaults: [included_paths: [~r"_test\.exs$"]],
    explanations: [
      check: """
      Tests must exercise behaviour through the public API, not inspect the TEXT
      or AST of production source files.

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

          # A literal source read.
          @impl_source "lib/forge_symphony/.../implementation.ex"
          source = File.read!(@impl_source)
          assert source =~ "%StepFailure{}"

          # Source paths carried as DATA, then read + parsed dynamically. Same
          # anti-pattern, one indirection removed.
          @registry [%{id: :x, file: "lib/forge_symphony/.../step.ex"}]
          defp source_ast(rel), do: rel |> File.read!() |> Code.string_to_quoted!()

      ## Good

          assert {:ok, %{status: :failed, error: :boom}} =
                   Implementation.validate_dispatch_result(%StepFailure{error: :boom}, ...)

      ## What is flagged

      Within test files (`included_paths`, default `[~r"_test\\.exs$"]`):

        * a module attribute whose value IS a `lib/*.ex` path
          (`@impl_source "lib/.../x.ex"`);
        * `File.read!` / `File.read` / `File.stream!` with a literal `lib/*.ex`
          argument;
        * `Code.string_to_quoted` (and the `!`, `_with_comments`, `eval_string`,
          `eval_file` variants) on a literal `lib/*.ex` path, OR anywhere in a
          file that also carries `lib/*.ex` paths as data -- the dynamic-path
          form that reads a table of source files and parses each.

      Carrying a `lib/*.ex` path as plain data (a routing-decision fixture, an
      ADR-rules JSON blob) is NOT flagged on its own: only reading or parsing
      production source is. Reading generated or fixture files (paths that do not
      point at `lib/*.ex`) is not flagged, and parsing that only ever touches
      non-`lib` source (a meta-lint over the test tree) is left alone.
      """,
      params: [
        included_paths: "Paths (regexes or substrings) the check runs on (default: *_test.exs)."
      ]
    ]

  # A literal path argument to a reader/parser, e.g. `File.read!("lib/.../x.ex")`
  # or `File.read!(Path.join(root, "lib/.../x.ex"))`. Permits a leading segment
  # so a joined literal is still caught.
  @lib_source_pattern ~r{(^|/)lib/.+\.exs?$}

  # A string that IS a relative production source path (`lib/.../x.ex`). Used to
  # decide whether a file references production source as data. Anchored at the
  # start so a coverage line like "SF:/repo/lib/foo.ex" or an incidental prose
  # string is not a false positive.
  @lib_source_data_pattern ~r/^lib\/.+\.exs?$/

  @readers [:read!, :read, :stream!]
  @source_parsers [
    :string_to_quoted,
    :string_to_quoted!,
    :string_to_quoted_with_comments,
    :string_to_quoted_with_comments!,
    :eval_string,
    :eval_file
  ]

  @doc false
  def run(source_file, params \\ []) do
    if test_file?(source_file, params) do
      issue_meta = IssueMeta.for(source_file, params)
      lib_ref? = references_lib_source?(source_file)
      Credo.Code.prewalk(source_file, &traverse(&1, &2, issue_meta, lib_ref?))
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

  # Does the file embed any production source path (`lib/*.ex`) as a literal? A
  # true result means source paths are present as data, so a parsing call in the
  # file is treated as production-source inspection. A meta-lint that parses only
  # test source (and names no `lib` path) stays false and is left alone. This is
  # ONLY a gate for the parse rule -- carrying a lib path as data is not itself
  # flagged, since routing-decision and rules fixtures legitimately hold one.
  defp references_lib_source?(source_file) do
    Credo.Code.prewalk(source_file, &collect_lib_literal/2, false)
  end

  defp collect_lib_literal(ast, true), do: {ast, true}
  defp collect_lib_literal(ast, false), do: {ast, lib_data_literal?(ast)}

  defp lib_data_literal?(bin) when is_binary(bin), do: bin =~ @lib_source_data_pattern
  defp lib_data_literal?(_ast), do: false

  # A module attribute whose value IS a lib source path: `@impl_source "lib/.../x.ex"`.
  defp traverse({:@, meta, [{name, _, [arg]}]} = ast, issues, issue_meta, _lib_ref?)
       when is_atom(name) and is_binary(arg) do
    flag_if_lib(ast, issues, issue_meta, meta, "@#{name}", arg)
  end

  # `File.read!("lib/.../x.ex")` / `File.read(...)` / `File.stream!(...)`.
  defp traverse(
         {{:., _, [{:__aliases__, _, [:File]}, reader]}, meta, [arg | _]} = ast,
         issues,
         issue_meta,
         _lib_ref?
       )
       when reader in @readers and is_binary(arg) do
    flag_if_lib(ast, issues, issue_meta, meta, "File.#{reader}", arg)
  end

  # `Code.string_to_quoted!(...)` / `Code.eval_string(...)` and friends: parsing
  # or evaluating source. Flagged on a literal `lib/*.ex` argument, or anywhere
  # in a file that also carries `lib/*.ex` paths as data (the dynamic-path form
  # that reads a table of source files and parses each).
  defp traverse(
         {{:., _, [{:__aliases__, _, [:Code]}, parser]}, meta, args} = ast,
         issues,
         issue_meta,
         lib_ref?
       )
       when parser in @source_parsers do
    cond do
      literal_lib_arg?(args) ->
        {ast, [reader_issue(issue_meta, meta, "Code.#{parser}") | issues]}

      lib_ref? ->
        {ast, [parse_issue(issue_meta, meta, "Code.#{parser}") | issues]}

      true ->
        {ast, issues}
    end
  end

  defp traverse(ast, issues, _issue_meta, _lib_ref?), do: {ast, issues}

  defp literal_lib_arg?([arg | _]) when is_binary(arg), do: arg =~ @lib_source_pattern
  defp literal_lib_arg?(_args), do: false

  defp flag_if_lib(ast, issues, issue_meta, meta, trigger, arg) do
    if arg =~ @lib_source_pattern do
      {ast, [reader_issue(issue_meta, meta, trigger) | issues]}
    else
      {ast, issues}
    end
  end

  defp reader_issue(issue_meta, meta, trigger) do
    format_issue(issue_meta,
      message:
        "`#{trigger}` reads production source in a test. Verify behaviour by calling the real " <>
          "function (make it public if needed), not by inspecting source text.",
      trigger: trigger,
      line_no: Keyword.get(meta, :line)
    )
  end

  defp parse_issue(issue_meta, meta, trigger) do
    format_issue(issue_meta,
      message:
        "`#{trigger}` parses production source into an AST in a test (this file also carries " <>
          "`lib/*.ex` paths as data). Assert behaviour, not source structure.",
      trigger: trigger,
      line_no: Keyword.get(meta, :line)
    )
  end
end
