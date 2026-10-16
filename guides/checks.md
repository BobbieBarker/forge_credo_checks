# Check reference

Enable checks individually in `.credo.exs` using their full module names, such as
`{ForgeCredoChecks.FilterMap, []}`. Each module documents its examples, parameters,
and detection limits in the [published documentation](https://hexdocs.pm/forge_credo_checks/).

## Collections

| Check | Detects |
| --- | --- |
| `ForgeCredoChecks.FilterMap` | Separate filtering and mapping passes. |
| `ForgeCredoChecks.RejectMap` | Separate rejection and mapping passes. |
| `ForgeCredoChecks.MapReject` | Separate mapping and rejection passes. |
| `ForgeCredoChecks.MapRejectNil` | Mapping followed by a separate pass to remove `nil`. |
| `ForgeCredoChecks.MapNewFromInto` | Transforming into an empty map with `Enum.into/3`. |
| `ForgeCredoChecks.MapNewFromReduce` | Reducing into an empty map with `Map.put/3`. |
| `ForgeCredoChecks.ReverseListFirst` | Reversing a list to take its first element. |
| `ForgeCredoChecks.SortListFirst` | Sorting to take the first or last element. |

## Control flow and data contracts

| Check | Detects |
| --- | --- |
| `ForgeCredoChecks.WithBareBinding` | Plain `=` bindings in `with` chains. |
| `ForgeCredoChecks.WithElseClauses` | `with` expressions exceeding a configured number of `else` clauses. |
| `ForgeCredoChecks.WithResultTag` | Atom-tagged `with` matches outside a configured vocabulary. |
| `ForgeCredoChecks.MapGetWithOr` | `Map.get/2` followed by `\|\|`, which treats `false` as missing. |
| `ForgeCredoChecks.ChainedMapGet` | `Map.get/2` fallback chains joined with `\|\|`. |
| `ForgeCredoChecks.NoAnyOrTermTypes` | `any()` or `term()` in typespecs and type declarations. |
| `ForgeCredoChecks.NoCaseTrueFalse` | Boolean `case` branches on expressions other than plain variables. |
| `ForgeCredoChecks.NoUnnecessaryCatchAllRaise` | Unguarded catch-all clauses that only raise in functions with other clauses. |

## Readability and documentation

| Check | Detects |
| --- | --- |
| `ForgeCredoChecks.InconsistentParamNames` | Inconsistent positional parameter names across function clauses. |
| `ForgeCredoChecks.NoKernelShadowing` | Variable names that shadow common Kernel functions. |
| `ForgeCredoChecks.NoKernelOpInPipeline` | Pipelines into Kernel comparison and boolean operators. |
| `ForgeCredoChecks.NoInlineRegex` | Regex literals inside function bodies. |
| `ForgeCredoChecks.MultilineStringConcat` | String literals concatenated across multiple lines. |
| `ForgeCredoChecks.NoTicketReferences` | Configured ticket identifiers in comments and documentation. |

## Module design

| Check | Detects |
| --- | --- |
| `ForgeCredoChecks.ShortModuleName` | Module-name segments and explicit alias names below a minimum length. |
| `ForgeCredoChecks.NamespaceTrespassing` | Module definitions under reserved dependency namespaces. |
| `ForgeCredoChecks.OneModulePerFile` | Multiple module definitions in a source file. |
| `ForgeCredoChecks.FileLength` | Source files over a line limit and obsolete allowlist entries. |
| `ForgeCredoChecks.LargeStruct` | Structs at or above a configurable field count. |

## Runtime boundaries

| Check | Detects |
| --- | --- |
| `ForgeCredoChecks.UnsupervisedSpawn` | Raw process spawning and `Task.start` calls. |
| `ForgeCredoChecks.NoApplicationGetEnvInLib` | `Application.get_env` calls in configured library paths. |
| `ForgeCredoChecks.NoDetsInfoOpenGuard` | `:dets.info/1` guards around `:dets.open_file/2`. |
| `ForgeCredoChecks.PortProducerBoundary` | Subprocess and Req HTTP calls outside declared boundary paths. |
| `ForgeCredoChecks.TelemetryControlFlow` | Direct process messaging or GenServer calls in telemetry handlers. |

## Testing

| Check | Detects |
| --- | --- |
| `ForgeCredoChecks.NoSourceInspectionInTest` | Production-source reads, parsing, and path attributes in test files. |
| `ForgeCredoChecks.TaintedSourceInspection` | Matching or evaluating source text traced to file reads. |
| `ForgeCredoChecks.NoTelemetryAssertionsInTest` | Telemetry handler attachments and telemetry message assertions in tests. |
| `ForgeCredoChecks.NoGlobalPubSubWildcardRefute` | Negative PubSub assertions with entirely unbound payloads after a global subscription. |
| `ForgeCredoChecks.MimicCopyOutsideRegistry` | `Mimic.copy` calls and captures outside a designated registration point. |
| `ForgeCredoChecks.TimingAndPrivateStateGuard` | Sleep calls and direct reads or mutations of process state. |

## Project configuration

Choose checks that match your project's conventions. Path scope and exclusions
vary by check; consult the module documentation before enabling a check.

- `NoTicketReferences` requires a nonempty `:ticket_prefixes` list, for example
  `ticket_prefixes: ["FGE", "PAY"]`. Supply prefixes without trailing hyphens.
- `NamespaceTrespassing` uses a configured `:namespaces` list of top-level atoms,
  such as `:Phoenix`. Review the defaults against your dependencies.
- `PortProducerBoundary` needs `:subprocess_boundaries` and `:http_boundaries`
  paths for permitted calls. Both default to empty lists, so every supported
  subprocess and HTTP call in the checked files is flagged.
- Set `NoTelemetryAssertionsInTest`'s `:telemetry_event_roots` and
  `NoGlobalPubSubWildcardRefute`'s `:global_subscriptions` for your project's
  events and subscription functions; their defaults are Forge-specific.
- For `MimicCopyOutsideRegistry`, set the permitted `:registration_paths` and the
  `:registry` name used in diagnostic guidance. The default registry names a
  Forge module.
