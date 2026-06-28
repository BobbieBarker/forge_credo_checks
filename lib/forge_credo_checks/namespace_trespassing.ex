defmodule ForgeCredoChecks.NamespaceTrespassing do
  use Credo.Check,
    base_priority: :normal,
    category: :design,
    param_defaults: [
      namespaces: ~w(Plug Phoenix Ecto Jason Logger Credo Finch Req Oban Broadway
                     GenStage Telemetry Tesla Swoosh)a
    ],
    explanations: [
      check: """
      Do not define your modules inside a dependency's namespace.

      ## Why

      Defining `defmodule Phoenix.MyThing` (or any module whose top namespace
      belongs to a library you depend on) trespasses on that library's
      namespace. It reads as if the module ships with the dependency, invites
      collisions when the dependency later adds a module of the same name, and
      hides the module from your application's own namespace where readers look
      for it. Keep your modules under your application's namespace.

      ## Bad

          defmodule Phoenix.Helpers do
          defmodule Ecto.MyType do

      ## Good

          defmodule MyApp.Phoenix.Helpers do
          defmodule MyApp.EctoTypes.MyType do

      ## Configuration

      `namespaces` lists the reserved top namespaces. A module defined with one
      of them as its first segment flags. The default omits `Mix`, because
      `Mix.Tasks.*` is the required home for custom Mix tasks.
      """
    ]

  @doc false
  def run(source_file, params \\ []) do
    issue_meta = IssueMeta.for(source_file, params)
    reserved = Params.get(params, :namespaces, __MODULE__)
    Credo.Code.prewalk(source_file, &traverse(&1, &2, issue_meta, reserved))
  end

  defp traverse(
         {:defmodule, _meta, [{:__aliases__, meta, [top | _] = segments}, _body]} = ast,
         issues,
         issue_meta,
         reserved
       )
       when is_atom(top) do
    if top in reserved and length(segments) > 1 do
      {ast, [issue_for(issue_meta, segments, meta) | issues]}
    else
      {ast, issues}
    end
  end

  defp traverse(ast, issues, _issue_meta, _reserved), do: {ast, issues}

  defp issue_for(issue_meta, segments, meta) do
    name = Enum.join(segments, ".")

    format_issue(issue_meta,
      message: """
      `#{name}` is defined under the `#{hd(segments)}` namespace, which belongs to a \
      dependency. Define it under your application's own namespace instead.\
      """,
      trigger: name,
      line_no: Keyword.get(meta, :line)
    )
  end
end
