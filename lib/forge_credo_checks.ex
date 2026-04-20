defmodule ForgeCredoChecks do
  @moduledoc """
  Custom Credo checks targeting `Enum` anti-patterns that LLMs commonly produce.

  Stock Credo ships checks for `filter |> filter`, `reject |> reject`,
  `map |> join`, `map |> into`, etc. but not the cases where one operation
  composes with the *complementary* one. These checks fill that gap:

    * `ForgeCredoChecks.FilterMap` flags `Enum.filter |> Enum.map`
    * `ForgeCredoChecks.RejectMap` flags `Enum.reject |> Enum.map`
    * `ForgeCredoChecks.MapReject` flags `Enum.map |> Enum.reject`
    * `ForgeCredoChecks.MapRejectNil` flags `Enum.map |> Enum.reject(&is_nil/1)`

  Each suggests `Enum.flat_map/2` as the single-pass replacement.

  ## Usage

  Add to `.credo.exs`:

      {ForgeCredoChecks.FilterMap, []},
      {ForgeCredoChecks.RejectMap, []},
      {ForgeCredoChecks.MapReject, []},
      {ForgeCredoChecks.MapRejectNil, []},
  """
end
