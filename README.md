# ForgeCredoChecks

Additional [Credo](https://github.com/rrrene/credo) checks for readable, idiomatic
Elixir. Covers collection operations, control flow, module design, documentation,
and testing. Enable the checks that fit your project's conventions.

[Hex](https://hex.pm/packages/forge_credo_checks) ·
[Documentation](https://hexdocs.pm/forge_credo_checks/) ·
[Changelog](CHANGELOG.md)

## Installation

Requires Elixir 1.18 or later and Credo 1.7.

Add `forge_credo_checks` to your dependencies in `mix.exs`:

```elixir
defp deps do
  [
    {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
    {:forge_credo_checks, "~> 0.9", only: [:dev, :test], runtime: false}
  ]
end
```

Then run `mix deps.get`.

## Usage

Add checks under `extra` in `.credo.exs` to keep Credo's default checks enabled.
If you don't have a configuration file, create one with `mix credo gen.config`.

For example:

```elixir
%{
  configs: [
    %{
      name: "default",
      checks: %{
        extra: [
          {ForgeCredoChecks.FilterMap, []},
          {ForgeCredoChecks.WithBareBinding, []},
          {ForgeCredoChecks.NoInlineRegex, []}
        ]
      }
    }
  ]
}
```

Run the checks alongside your existing Credo rules:

```sh
mix credo --strict
```

## Available checks

The [check reference](guides/checks.md) lists every check by purpose. Each check's
module documentation includes its rationale, examples, configuration options,
and detection limits. Some checks require project-specific configuration, such
as ticket prefixes, namespaces, or permitted boundary paths.

The repository may include unreleased checks. See the [changelog](CHANGELOG.md)
for release status and [HexDocs](https://hexdocs.pm/forge_credo_checks/) for the
published version.

## License

[MIT](LICENSE)
