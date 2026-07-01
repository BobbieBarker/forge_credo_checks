defmodule ForgeCredoChecks do
  @moduledoc """
  Custom Credo checks targeting anti-patterns that LLMs commonly produce.

  Stock Credo ships checks for `filter |> filter`, `reject |> reject`,
  `map |> join`, `map |> into`, etc. but not the cases where one operation
  composes with the *complementary* one, nor the common map-building,
  sort-then-pick, and map-shape normalization anti-patterns. These checks fill
  those gaps.

  ## Two-pass Enum chains (suggests `Enum.reduce/3`)

    * `ForgeCredoChecks.FilterMap`: `Enum.filter |> Enum.map`
    * `ForgeCredoChecks.RejectMap`: `Enum.reject |> Enum.map`
    * `ForgeCredoChecks.MapReject`: `Enum.map |> Enum.reject`
    * `ForgeCredoChecks.MapRejectNil`: `Enum.map |> Enum.reject(&is_nil/1)`

  ## Hand-rolled map building (suggests `Map.new/2`)

    * `ForgeCredoChecks.MapNewFromInto`: `Enum.into(%{}, fn ...)`
    * `ForgeCredoChecks.MapNewFromReduce`: `Enum.reduce(_, %{}, &Map.put(acc, k, v))`

  ## Wasteful list-extremum patterns

    * `ForgeCredoChecks.ReverseListFirst`: `xs |> Enum.reverse() |> List.first()` becomes `List.last(xs)`
    * `ForgeCredoChecks.SortListFirst`: `Enum.sort \\| List.first` becomes `Enum.min`/`Enum.max`/`*_by`

  ## Map shape normalization

    * `ForgeCredoChecks.MapGetWithOr`: `Map.get(_, _) || fallback`
    * `ForgeCredoChecks.ChainedMapGet`: `Map.get(_, _) || Map.get(_, _)`

  ## LLM tells

    * `ForgeCredoChecks.NoInlineRegex`: inline `~r`/`~R` regex sigils inside function bodies
  """
end
