defmodule ForgeCredoChecks.PortProducerBoundary do
  use Credo.Check,
    base_priority: :high,
    category: :warning,
    param_defaults: [
      subprocess_boundaries: [],
      http_boundaries: [],
      excluded_paths: [~r"^test/"]
    ],
    explanations: [
      check: """
      External-model producers belong only in declared boundary modules.

      ## Why

      A port is the boundary where an external model (a subprocess's bytes, an
      HTTP response) is (de)serialized into the application's internal model.
      The invariant is that an external model never reaches the core
      un-deserialized. The way to guarantee that by construction is to fence
      the *producer calls* that emit external models (`System.cmd`, `Req.post`,
      and friends) to a small set of declared boundary modules. If every
      producer lives behind a boundary, no external model can exist in the core.

      This check is the generalization of "no raw `Repo` outside the context" to
      every I/O faucet. Detection is **module/path membership, never first
      argument inspection**: executables are routinely invoked through bound
      variables (`gh_path = System.find_executable("gh")` then
      `System.cmd(gh_path, args)`), so matching on the literal command would let
      real ports through and flag innocent tooling. The check instead asks a
      single question per producer call: does the file it lives in match a
      declared boundary glob for that producer's family?

      Producer families are keyed separately, and a call in the wrong family's
      boundary still fails (a `Req` call inside a subprocess-only boundary is an
      issue):

        * `subprocess`: `System.cmd/2,3`, `System.shell/1`, `:os.cmd/1`,
          `Port.open/2`, `:erlang.open_port/2`
        * `http`: `Req.{get,post,put,patch,delete,request}` and their `!`
          variants. `Req.new/1` only builds a request struct and performs no
          I/O, so it is not flagged.

      ## Out of scope

      The following are deliberately **not** flagged, because including any of
      them makes the check false-positive-noisy: `File.*`, `:ets`/`:dets`,
      `Repo`/`Ecto`, and `Jason.decode`. They are not external-model producers in
      the ports-and-adapters sense this check enforces.

      ## Known limits

      Detection is syntactic: the check reads the raw AST and does not resolve
      aliases. A few constructs therefore bypass it by design rather than being
      caught: an aliased module (`alias Req, as: HTTP; HTTP.post(...)`), an
      imported call (`import System; cmd(...)`), a dynamic dispatch
      (`apply(System, :cmd, args)`), and a producer reached through a
      user-defined module whose final segment collides with `System`/`Req`.
      Closing them would require whole-program semantic analysis; they are
      documented here so the boundary the check leaves open is explicit.

      ## Bad

          # in lib/forge/core/runner.ex — not a declared boundary
          System.cmd("gh", ["pr", "view"])

      ## Good

          # in lib/forge/ports/gh.ex — matches a subprocess_boundaries glob
          System.cmd("gh", ["pr", "view"])

      ## Configuration

      `subprocess_boundaries` and `http_boundaries` are lists of patterns
      (regexes or substrings) matched against each file's path; a producer of
      that family is allowed only in a file whose path matches. `excluded_paths`
      (default `[~r"^test/"]`) lists paths skipped entirely.

          {ForgeCredoChecks.PortProducerBoundary,
           subprocess_boundaries: [~r"^lib/forge/ports/"],
           http_boundaries: [~r"^lib/forge/adapters/"]}

      This check's category is `:warning`, which in Credo still contributes a
      non-zero exit status. A plain registration therefore hard-fails the build
      the first time any producer is flagged. For a warning-first rollout you
      MUST set `exit_status: 0` at registration, and drop it (letting the
      `:warning` exit status apply) only once the boundary modules exist and the
      scatter is contained:

          # warning phase: reports issues but does not fail CI
          {ForgeCredoChecks.PortProducerBoundary,
           exit_status: 0,
           subprocess_boundaries: [~r"/ports/"]}

          # hard gate: drop exit_status to let the :warning status apply
          {ForgeCredoChecks.PortProducerBoundary,
           subprocess_boundaries: [~r"/ports/"]}

      Credo's `# credo:disable-for-next-line` escape hatch is honored
      automatically; when rolling this out as a real boundary, pair it with a CI
      check that rejects net-new disables of this rule.
      """,
      params: [
        subprocess_boundaries:
          "Paths (regexes or substrings) allowed to host subprocess producers.",
        http_boundaries: "Paths (regexes or substrings) allowed to host HTTP producers.",
        excluded_paths: "Paths skipped entirely (regexes or substrings)."
      ]
    ]

  @req_verbs [
    :post,
    :get,
    :put,
    :patch,
    :delete,
    :request,
    :post!,
    :get!,
    :put!,
    :patch!,
    :delete!,
    :request!
  ]

  @doc false
  def run(source_file, params \\ []) do
    if excluded_path?(source_file, params) do
      []
    else
      issue_meta = IssueMeta.for(source_file, params)
      subprocess = Params.get(params, :subprocess_boundaries, __MODULE__)
      http = Params.get(params, :http_boundaries, __MODULE__)
      path = source_file.filename
      Credo.Code.prewalk(source_file, &traverse(&1, &2, issue_meta, path, subprocess, http))
    end
  end

  defp excluded_path?(%{filename: filename}, params) when is_binary(filename) do
    params
    |> Params.get(:excluded_paths, __MODULE__)
    |> Enum.any?(&(filename =~ &1))
  end

  defp excluded_path?(_source_file, _params), do: false

  # captures ---------------------------------------------------------------

  # A function capture like `&System.cmd/3` or `&Req.get/1` is a reference, not
  # a call site: no external model is produced where it is written. Neutralize
  # the inner remote node so the producer clauses below do not flag the capture
  # when prewalk descends into it. Local captures (`&spawn/1`) do not match and
  # are left untouched. The `&System.cmd(&1, &2)` partial-application form is a
  # deferred call, not a bare reference, and is deliberately still flagged.
  defp traverse(
         {:&, amp_meta, [{:/, slash_meta, [{{:., _, [_mod, _fun]}, _dot_meta, []}, arity]}]},
         issues,
         _issue_meta,
         _path,
         _subprocess,
         _http
       )
       when is_integer(arity) do
    {{:&, amp_meta, [{:/, slash_meta, [:__captured_producer__, arity]}]}, issues}
  end

  # subprocess family ------------------------------------------------------

  defp traverse(
         {{:., _, [{:__aliases__, _, [:System]}, :cmd]}, meta, args} = ast,
         issues,
         issue_meta,
         path,
         subprocess,
         _http
       )
       when is_list(args) do
    flag(ast, issues, issue_meta, path, subprocess, :subprocess, "System.cmd", meta)
  end

  defp traverse(
         {{:., _, [{:__aliases__, _, [:System]}, :shell]}, meta, args} = ast,
         issues,
         issue_meta,
         path,
         subprocess,
         _http
       )
       when is_list(args) do
    flag(ast, issues, issue_meta, path, subprocess, :subprocess, "System.shell", meta)
  end

  defp traverse(
         {{:., _, [:os, :cmd]}, meta, args} = ast,
         issues,
         issue_meta,
         path,
         subprocess,
         _http
       )
       when is_list(args) do
    flag(ast, issues, issue_meta, path, subprocess, :subprocess, ":os.cmd", meta)
  end

  defp traverse(
         {{:., _, [{:__aliases__, _, [:Port]}, :open]}, meta, args} = ast,
         issues,
         issue_meta,
         path,
         subprocess,
         _http
       )
       when is_list(args) do
    flag(ast, issues, issue_meta, path, subprocess, :subprocess, "Port.open", meta)
  end

  defp traverse(
         {{:., _, [:erlang, :open_port]}, meta, args} = ast,
         issues,
         issue_meta,
         path,
         subprocess,
         _http
       )
       when is_list(args) do
    flag(ast, issues, issue_meta, path, subprocess, :subprocess, ":erlang.open_port", meta)
  end

  # http family ------------------------------------------------------------

  defp traverse(
         {{:., _, [{:__aliases__, _, [:Req]}, verb]}, meta, args} = ast,
         issues,
         issue_meta,
         path,
         _subprocess,
         http
       )
       when verb in @req_verbs and is_list(args) do
    flag(ast, issues, issue_meta, path, http, :http, "Req.#{verb}", meta)
  end

  defp traverse(ast, issues, _issue_meta, _path, _subprocess, _http), do: {ast, issues}

  defp flag(ast, issues, issue_meta, path, boundaries, family, name, meta) do
    if in_boundary?(path, boundaries) do
      {ast, issues}
    else
      {ast, [issue_for(issue_meta, family, name, meta) | issues]}
    end
  end

  # A non-binary filename (e.g. an in-memory "nofile") cannot be assessed for
  # boundary membership, so it is treated as in-boundary rather than flagged.
  defp in_boundary?(path, boundaries) when is_binary(path) do
    Enum.any?(boundaries, &(path =~ &1))
  end

  defp in_boundary?(_path, _boundaries), do: true

  defp issue_for(issue_meta, family, name, meta) do
    format_issue(issue_meta,
      message: message_for(family, name),
      trigger: name,
      line_no: Keyword.get(meta, :line)
    )
  end

  defp message_for(:subprocess, name) do
    "`#{name}` is a subprocess external-model producer called outside a declared boundary. " <>
      "Move this call into a module whose path matches one of `subprocess_boundaries`, so " <>
      "external models stay deserialized at the port and cannot leak into the core."
  end

  defp message_for(:http, name) do
    "`#{name}` is an HTTP external-model producer called outside a declared boundary. " <>
      "Move this call into a module whose path matches one of `http_boundaries`, so " <>
      "external models stay deserialized at the port and cannot leak into the core."
  end
end
