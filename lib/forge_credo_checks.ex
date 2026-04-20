defmodule ForgeCredoChecks do
  @moduledoc """
  Custom Credo checks targeting `Enum` anti-patterns that LLMs commonly produce.

  Stock Credo ships checks for `filter |> filter`, `reject |> reject`,
  `map |> join`, `map |> into`, etc. but not the cases where one operation
  composes with the *complementary* one, nor the common map-building and
  sort-then-pick anti-patterns. These checks fill those gaps.

  ## Two-pass Enum chains (suggests `Enum.reduce/3`)

    * `ForgeCredoChecks.FilterMap` — `Enum.filter |> Enum.map`
    * `ForgeCredoChecks.RejectMap` — `Enum.reject |> Enum.map`
    * `ForgeCredoChecks.MapReject` — `Enum.map |> Enum.reject`
    * `ForgeCredoChecks.MapRejectNil` — `Enum.map |> Enum.reject(&is_nil/1)`

  ## Hand-rolled map building (suggests `Map.new/2`)

    * `ForgeCredoChecks.MapNewFromInto` — `Enum.into(%{}, fn ...)`
    * `ForgeCredoChecks.MapNewFromReduce` — `Enum.reduce(_, %{}, &Map.put(acc, k, v))`

  ## Wasteful list-extremum patterns

    * `ForgeCredoChecks.ReverseListFirst` — `xs |> Enum.reverse() |> List.first()` → `List.last(xs)`
    * `ForgeCredoChecks.SortListFirst` — `Enum.sort \\| List.first` → `Enum.min`/`Enum.max`/`*_by`
  """
end
