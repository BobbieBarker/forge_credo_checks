defmodule ForgeCredoChecks.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/bobbiebarker/forge_credo_checks"

  def project do
    [
      app: :forge_credo_checks,
      version: @version,
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: description(),
      package: package(),
      source_url: @source_url
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
      {:ex_doc, "~> 0.34", only: :dev, runtime: false}
    ]
  end

  defp description do
    "Custom Credo checks targeting Enum anti-patterns LLMs commonly generate " <>
      "(filter |> map, map |> reject(is_nil), etc.)"
  end

  defp package do
    [
      maintainers: ["Chad King"],
      licenses: ["MIT"],
      files: ~w(lib mix.exs README.md LICENSE),
      links: %{"GitHub" => @source_url}
    ]
  end
end
