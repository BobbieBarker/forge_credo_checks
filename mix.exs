defmodule ForgeCredoChecks.MixProject do
  use Mix.Project

  @version "0.10.0"
  @source_url "https://github.com/BobbieBarker/forge_credo_checks"

  def project do
    [
      app: :forge_credo_checks,
      version: @version,
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: description(),
      package: package(),
      source_url: @source_url,
      homepage_url: @source_url,
      docs: docs(),
      dialyzer: dialyzer()
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:credo, "~> 1.7"},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev], runtime: false}
    ]
  end

  defp description do
    "Additional Credo checks for readable, idiomatic Elixir."
  end

  defp package do
    [
      maintainers: ["Chad King"],
      licenses: ["MIT"],
      files: ~w(lib guides mix.exs README.md LICENSE CHANGELOG.md),
      links: %{"GitHub" => @source_url, "Changelog" => "#{@source_url}/blob/main/CHANGELOG.md"}
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: ["README.md", "guides/checks.md", "CHANGELOG.md", "LICENSE"],
      # This internal Elixir module is a naming example with no public docs to link.
      skip_code_autolink_to: ["Module.Types.Of"],
      groups_for_modules: [
        Collections: [
          ForgeCredoChecks.FilterMap,
          ForgeCredoChecks.RejectMap,
          ForgeCredoChecks.MapReject,
          ForgeCredoChecks.MapRejectNil,
          ForgeCredoChecks.MapNewFromInto,
          ForgeCredoChecks.MapNewFromReduce,
          ForgeCredoChecks.ReverseListFirst,
          ForgeCredoChecks.SortListFirst
        ],
        "Control flow and data contracts": [
          ForgeCredoChecks.WithBareBinding,
          ForgeCredoChecks.WithElseClauses,
          ForgeCredoChecks.WithResultTag,
          ForgeCredoChecks.MapGetWithOr,
          ForgeCredoChecks.ChainedMapGet,
          ForgeCredoChecks.NoAnyOrTermTypes,
          ForgeCredoChecks.NoCaseTrueFalse,
          ForgeCredoChecks.NoUnnecessaryCatchAllRaise
        ],
        "Readability and documentation": [
          ForgeCredoChecks.InconsistentParamNames,
          ForgeCredoChecks.NoKernelShadowing,
          ForgeCredoChecks.NoKernelOpInPipeline,
          ForgeCredoChecks.NoInlineRegex,
          ForgeCredoChecks.MultilineStringConcat,
          ForgeCredoChecks.NoTicketReferences
        ],
        "Module design": [
          ForgeCredoChecks.ShortModuleName,
          ForgeCredoChecks.NamespaceTrespassing,
          ForgeCredoChecks.OneModulePerFile,
          ForgeCredoChecks.FileLength,
          ForgeCredoChecks.LargeStruct
        ],
        "Runtime boundaries": [
          ForgeCredoChecks.UnsupervisedSpawn,
          ForgeCredoChecks.NoApplicationGetEnvInLib,
          ForgeCredoChecks.NoDetsInfoOpenGuard,
          ForgeCredoChecks.PortProducerBoundary,
          ForgeCredoChecks.TelemetryControlFlow
        ],
        Testing: [
          ForgeCredoChecks.NoSourceInspectionInTest,
          ForgeCredoChecks.TaintedSourceInspection,
          ForgeCredoChecks.NoTelemetryAssertionsInTest,
          ForgeCredoChecks.NoGlobalPubSubWildcardRefute,
          ForgeCredoChecks.MimicCopyOutsideRegistry,
          ForgeCredoChecks.TimingAndPrivateStateGuard
        ]
      ],
      source_ref: "v#{@version}",
      source_url: @source_url
    ]
  end

  defp dialyzer do
    [
      plt_file: {:no_warn, "priv/plts/dialyzer.plt"},
      plt_add_apps: [:credo, :mix]
    ]
  end
end
