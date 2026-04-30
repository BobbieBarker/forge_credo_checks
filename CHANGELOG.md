# Changelog

## 0.2.0

First Hex release.

Adds four checks beyond the original two-pass `Enum` chain set:

- `ForgeCredoChecks.MapNewFromInto`: `Enum.map |> Enum.into(%{}, ...)` becomes `Map.new/2`
- `ForgeCredoChecks.MapNewFromReduce`: `Enum.reduce(_, %{}, &Map.put(acc, k, v))` becomes `Map.new/2`
- `ForgeCredoChecks.ReverseListFirst`: `xs |> Enum.reverse() |> List.first()` becomes `List.last(xs)`
- `ForgeCredoChecks.SortListFirst`: `Enum.sort |> List.first` becomes `Enum.min`/`Enum.max`/`*_by`

Carried over from 0.1.x:

- `ForgeCredoChecks.FilterMap`: `Enum.filter |> Enum.map`
- `ForgeCredoChecks.RejectMap`: `Enum.reject |> Enum.map`
- `ForgeCredoChecks.MapReject`: `Enum.map |> Enum.reject`
- `ForgeCredoChecks.MapRejectNil`: `Enum.map |> Enum.reject(&is_nil/1)`
