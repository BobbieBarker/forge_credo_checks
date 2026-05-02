defmodule ForgeCredoChecks.WithResultTag do
  use Credo.Check,
    base_priority: :normal,
    category: :refactor,
    param_defaults: [allowed_atoms: [:ok, :error]],
    explanations: [
      check: """
      `<-` clauses in a `with` chain should use a consistent vocabulary of
      result tags. The default is `:ok | {:error, reason}` or
      `{:ok, value} | {:error, reason}` - every step in the chain returns
      one of those shapes, so a non-match falls through cleanly without
      needing an `else` block to sort by step-specific tags.

      ## How to fix

      Two options when this fires:

      **Option 1 - change the called function** to return an allowed shape
      (typically `{:ok, _} | {:error, _}`):

          # BEFORE - returns {:found, user} | nil
          def lookup(id), do: Repo.get(User, id) |> wrap_found()

          # AFTER - returns {:ok, user} | {:error, :not_found}
          def lookup(id) do
            case Repo.get(User, id) do
              nil -> {:error, :not_found}
              user -> {:ok, user}
            end
          end

      Then the `with` clause becomes `{:ok, user} <- lookup(id)` and falls
      through cleanly.

      **Option 2 - add the atom to `:allowed_atoms`** in `.credo.exs` if
      it's part of this codebase's intentional vocabulary (e.g. a
      domain-specific control-flow tag like `:found`, `:retry`, `:locked`):

          {ForgeCredoChecks.WithResultTag,
           allowed_atoms: [:ok, :error, :found, :retry]}

      ## What NOT to do

      Do not bypass this check by switching the LHS to a variable or
      wildcard just to silence it:

          # STILL BAD - loses the contract entirely
          with result <- lookup(id), ...
          with _ <- lookup(id), ...

      Pick option 1 (normalize the return) or option 2 (extend the
      allowlist) - both are accepted; the variable-shrug is not.

      ## Scope

      Only atom-tagged shapes are checked: bare atoms (`:foo <-`), 2-tuples
      (`{:foo, _} <-`), and 3+-tuples (`{:foo, a, b} <-`). Variables,
      pinned variables, struct matches, list patterns, and other complex
      patterns are not checked.
      """,
      params: [
        allowed_atoms:
          "Atoms permitted as a `<-` LHS or as the tag of a `{tag, _}` LHS. " <>
            "Default: `[:ok, :error]`."
      ]
    ]

  @doc false
  def run(source_file, params \\ []) do
    issue_meta = IssueMeta.for(source_file, params)
    allowed = Params.get(params, :allowed_atoms, __MODULE__)
    Credo.Code.prewalk(source_file, &traverse(&1, &2, issue_meta, allowed))
  end

  defp traverse({:with, _meta, args} = ast, issues, issue_meta, allowed)
       when is_list(args) do
    new_issues =
      args
      |> Enum.drop(-1)
      |> Enum.flat_map(&issue_for_clause(&1, issue_meta, allowed))

    {ast, issues ++ new_issues}
  end

  defp traverse(ast, issues, _issue_meta, _allowed), do: {ast, issues}

  # Bare atom LHS: :foo <- expr (skip nil/true/false - rarely meaningful here)
  defp issue_for_clause({:<-, meta, [tag, _rhs]}, issue_meta, allowed)
       when is_atom(tag) and not is_nil(tag) and not is_boolean(tag) do
    flag(tag, meta, issue_meta, allowed)
  end

  # 2-tuple tagged LHS: {:foo, pat} <- expr (literal 2-tuple in AST)
  defp issue_for_clause({:<-, meta, [{tag, _pat}, _rhs]}, issue_meta, allowed)
       when is_atom(tag) and not is_nil(tag) and not is_boolean(tag) do
    flag(tag, meta, issue_meta, allowed)
  end

  # 3+-tuple tagged LHS: {:foo, a, b, ...} <- expr ({:{}, _, [tag | rest]} in AST)
  defp issue_for_clause(
         {:<-, meta, [{:{}, _, [tag | _]}, _rhs]},
         issue_meta,
         allowed
       )
       when is_atom(tag) and not is_nil(tag) and not is_boolean(tag) do
    flag(tag, meta, issue_meta, allowed)
  end

  defp issue_for_clause(_, _, _), do: []

  defp flag(tag, meta, issue_meta, allowed) do
    if tag in allowed do
      []
    else
      [
        format_issue(issue_meta,
          message:
            "`with` clause uses tag `#{inspect(tag)}`, which is not in `:allowed_atoms` " <>
              "(#{inspect(allowed)}). Fix: either (1) change the called function to " <>
              "return an allowed shape (typically `{:ok, _} | {:error, _}`) and update " <>
              "this LHS to match, or (2) if `#{inspect(tag)}` is intentional vocabulary " <>
              "in this project, add it to `:allowed_atoms` for this check in `.credo.exs`. " <>
              "Do NOT replace the LHS with a bare variable or `_` to silence the check.",
          trigger: inspect(tag),
          line_no: meta[:line]
        )
      ]
    end
  end
end
