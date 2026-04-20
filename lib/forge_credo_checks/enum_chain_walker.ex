defmodule ForgeCredoChecks.EnumChainWalker do
  @moduledoc false

  # Walks AST looking for `Enum.<first>(...)` followed by `Enum.<second>(...)`
  # in any of the four shapes the Elixir parser can produce:
  #
  #   1. Enum.second(Enum.first(x, f), g)              — direct nested call
  #   2. x |> Enum.first(f) |> Enum.second(g)          — two-step pipe
  #   3. Enum.second(x |> Enum.first(f), g)            — partial pipe + call
  #   4. x |> y |> Enum.first(f) |> Enum.second(g)     — pipe chain (3+)
  #
  # `report_fn` receives `(line, second_predicate)` where `second_predicate`
  # is the last arg of the `second` call (the function passed to filter/map/
  # reject). Returning a non-nil issue records it; returning `nil` skips.

  def traverse(
        {{:., _, [{:__aliases__, meta, [:Enum]}, second]}, _,
         [{{:., _, [{:__aliases__, _, [:Enum]}, first]}, _, _}, second_pred]} = ast,
        issues,
        first,
        second,
        report_fn
      ) do
    {ast, issues ++ List.wrap(report_fn.(meta[:line], second_pred))}
  end

  def traverse(
        {:|>, meta,
         [
           {{:., _, [{:__aliases__, _, [:Enum]}, first]}, _, _},
           {{:., _, [{:__aliases__, _, [:Enum]}, second]}, _, [second_pred]}
         ]} = ast,
        issues,
        first,
        second,
        report_fn
      ) do
    {ast, issues ++ List.wrap(report_fn.(meta[:line], second_pred))}
  end

  def traverse(
        {{:., meta, [{:__aliases__, _, [:Enum]}, second]}, _,
         [
           {:|>, _, [_, {{:., _, [{:__aliases__, _, [:Enum]}, first]}, _, _}]},
           second_pred
         ]} = ast,
        issues,
        first,
        second,
        report_fn
      ) do
    {ast, issues ++ List.wrap(report_fn.(meta[:line], second_pred))}
  end

  def traverse(
        {:|>, meta,
         [
           {:|>, _,
            [
              _,
              {{:., _, [{:__aliases__, _, [:Enum]}, first]}, _, _}
            ]},
           {{:., _, [{:__aliases__, _, [:Enum]}, second]}, _, [second_pred]}
         ]} = ast,
        issues,
        first,
        second,
        report_fn
      ) do
    {ast, issues ++ List.wrap(report_fn.(meta[:line], second_pred))}
  end

  def traverse(ast, issues, _first, _second, _report_fn) do
    {ast, issues}
  end

  # Predicate inspectors — used by checks that care about the second call's
  # argument shape (e.g. MapRejectNil wants reject's predicate to be `&is_nil/1`).

  def is_nil_predicate?({:&, _, [{:/, _, [{:is_nil, _, _}, 1]}]}), do: true

  def is_nil_predicate?({:&, _, [{:==, _, [{:&, _, [1]}, nil]}]}), do: true

  def is_nil_predicate?({:&, _, [{:===, _, [{:&, _, [1]}, nil]}]}), do: true

  def is_nil_predicate?(
        {:fn, _,
         [{:->, _, [[{name, _, ctx1}], {:is_nil, _, [{name, _, ctx2}]}]}]}
      )
      when is_atom(name) and is_atom(ctx1) and is_atom(ctx2),
      do: true

  def is_nil_predicate?(
        {:fn, _,
         [{:->, _, [[{name, _, ctx1}], {op, _, [{name, _, ctx2}, nil]}]}]}
      )
      when op in [:==, :===] and is_atom(name) and is_atom(ctx1) and is_atom(ctx2),
      do: true

  def is_nil_predicate?(_), do: false
end
