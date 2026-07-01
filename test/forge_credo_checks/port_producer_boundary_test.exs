defmodule ForgeCredoChecks.PortProducerBoundaryTest do
  use Credo.Test.Case

  alias Credo.Check.ConfigComment
  alias ForgeCredoChecks.PortProducerBoundary

  @subprocess [~r"^lib/forge/ports/"]
  @http [~r"^lib/forge/adapters/linear"]

  defp boundaries(extra \\ []) do
    Keyword.merge([subprocess_boundaries: @subprocess, http_boundaries: @http], extra)
  end

  test "no issue: subprocess producer inside a declared subprocess boundary" do
    """
    defmodule Forge.Ports.Gh do
      def run(args), do: System.cmd("gh", args)
    end
    """
    |> to_source_file("lib/forge/ports/gh.ex")
    |> run_check(PortProducerBoundary, boundaries())
    |> refute_issues()
  end

  test "issue: subprocess producer outside any boundary, flagged at the call line" do
    """
    defmodule Forge.Core.Runner do
      def run(args) do
        System.cmd("gh", args)
      end
    end
    """
    |> to_source_file("lib/forge/core/runner.ex")
    |> run_check(PortProducerBoundary, boundaries())
    |> assert_issue(%{line_no: 3, trigger: "System.cmd"})
  end

  test "issue: bound-var executable is flagged (detection is module/path, not first-arg)" do
    """
    defmodule Forge.Core.Runner do
      def run(args) do
        gh_path = System.find_executable("gh")
        System.cmd(gh_path, args)
      end
    end
    """
    |> to_source_file("lib/forge/core/runner.ex")
    |> run_check(PortProducerBoundary, boundaries())
    |> assert_issue(%{line_no: 4, trigger: "System.cmd"})
  end

  test "issue: System.cmd/3 (with opts) is flagged outside a boundary" do
    """
    defmodule Forge.Core.Runner do
      def run(args), do: System.cmd("gh", args, cd: "/tmp")
    end
    """
    |> to_source_file("lib/forge/core/runner.ex")
    |> run_check(PortProducerBoundary, boundaries())
    |> assert_issue(%{trigger: "System.cmd"})
  end

  test "no issue: System.cmd/3 inside a declared subprocess boundary" do
    """
    defmodule Forge.Ports.Gh do
      def run(args), do: System.cmd("gh", args, cd: "/tmp")
    end
    """
    |> to_source_file("lib/forge/ports/gh.ex")
    |> run_check(PortProducerBoundary, boundaries())
    |> refute_issues()
  end

  test "issue: Port.open and :erlang.open_port outside a boundary" do
    """
    defmodule Forge.Core.Runner do
      def a(name), do: Port.open(name, [:binary])
      def b(name), do: :erlang.open_port(name, [:binary])
    end
    """
    |> to_source_file("lib/forge/core/runner.ex")
    |> run_check(PortProducerBoundary, boundaries())
    |> assert_issues()
  end

  test "no issue: Port.open and :erlang.open_port inside a declared subprocess boundary" do
    """
    defmodule Forge.Ports.Gh do
      def a(name), do: Port.open(name, [:binary])
      def b(name), do: :erlang.open_port(name, [:binary])
    end
    """
    |> to_source_file("lib/forge/ports/gh.ex")
    |> run_check(PortProducerBoundary, boundaries())
    |> refute_issues()
  end

  test "no issue: http producer inside a declared http boundary" do
    """
    defmodule Forge.Adapters.LinearClient do
      def create(body), do: Req.post("https://api.linear.app", json: body)
    end
    """
    |> to_source_file("lib/forge/adapters/linear_client.ex")
    |> run_check(PortProducerBoundary, boundaries())
    |> refute_issues()
  end

  test "issue: every executing Req verb (put/patch/delete/request) is flagged outside a boundary" do
    triggers =
      """
      defmodule Forge.Core.Runner do
        def a(url), do: Req.put(url, json: %{})
        def b(url), do: Req.patch(url, json: %{})
        def c(url), do: Req.delete(url)
        def d(url), do: Req.request(url: url)
      end
      """
      |> to_source_file("lib/forge/core/runner.ex")
      |> run_check(PortProducerBoundary, boundaries())
      |> Enum.map(& &1.trigger)
      |> Enum.sort()

    assert triggers == ["Req.delete", "Req.patch", "Req.put", "Req.request"]
  end

  test "no issue: every executing Req verb inside a declared http boundary" do
    """
    defmodule Forge.Adapters.LinearClient do
      def a(url), do: Req.put(url, json: %{})
      def b(url), do: Req.patch(url, json: %{})
      def c(url), do: Req.delete(url)
      def d(url), do: Req.request(url: url)
    end
    """
    |> to_source_file("lib/forge/adapters/linear_client.ex")
    |> run_check(PortProducerBoundary, boundaries())
    |> refute_issues()
  end

  test "issue: Req call inside a subprocess-only boundary fails (wrong family)" do
    """
    defmodule Forge.Ports.Gh do
      def fetch(url), do: Req.get(url)
    end
    """
    |> to_source_file("lib/forge/ports/gh.ex")
    |> run_check(PortProducerBoundary, boundaries())
    |> assert_issue(%{trigger: "Req.get"})
  end

  test "issue: subprocess call inside an http-only boundary fails (wrong family, symmetric)" do
    """
    defmodule Forge.Adapters.LinearClient do
      def run(args), do: System.cmd("gh", args)
    end
    """
    |> to_source_file("lib/forge/adapters/linear_client.ex")
    |> run_check(PortProducerBoundary, boundaries())
    |> assert_issue(%{trigger: "System.cmd"})
  end

  test "issue: http producer outside any boundary, flagged at the call line" do
    """
    defmodule Forge.Core.Runner do
      def fetch(url) do
        Req.post(url, json: %{})
      end
    end
    """
    |> to_source_file("lib/forge/core/runner.ex")
    |> run_check(PortProducerBoundary, boundaries())
    |> assert_issue(%{line_no: 3, trigger: "Req.post"})
  end

  test "subprocess issue message names the producer and points at the subprocess boundary" do
    issue =
      """
      defmodule Forge.Core.Runner do
        def run(args), do: System.cmd("gh", args)
      end
      """
      |> to_source_file("lib/forge/core/runner.ex")
      |> run_check(PortProducerBoundary, boundaries())
      |> assert_issue()
      |> List.first()

    assert issue.message =~ "System.cmd"
    assert issue.message =~ "subprocess_boundaries"
    assert issue.message =~ "Move this call into"
  end

  test "http issue message names the producer and points at the http boundary" do
    issue =
      """
      defmodule Forge.Core.Runner do
        def fetch(url), do: Req.post(url, json: %{})
      end
      """
      |> to_source_file("lib/forge/core/runner.ex")
      |> run_check(PortProducerBoundary, boundaries())
      |> assert_issue()
      |> List.first()

    assert issue.message =~ "Req.post"
    assert issue.message =~ "http_boundaries"
    assert issue.message =~ "Move this call into"
  end

  test "no issue: producer in an excluded_paths file (default excludes test/)" do
    """
    defmodule Forge.RunnerTest do
      def run(args), do: System.cmd("gh", args)
    end
    """
    |> to_source_file("test/forge/runner_test.exs")
    |> run_check(PortProducerBoundary, boundaries())
    |> refute_issues()
  end

  test "issue: producer still flagged when excluded_paths does not match" do
    """
    defmodule Forge.Core.Runner do
      def run(args), do: System.cmd("gh", args)
    end
    """
    |> to_source_file("lib/forge/core/runner.ex")
    |> run_check(PortProducerBoundary, boundaries(excluded_paths: [~r"^bench/"]))
    |> assert_issue()
  end

  test "no issue: out-of-scope I/O is never flagged" do
    """
    defmodule Forge.Core.Store do
      def a, do: File.write("x", "y")
      def b, do: :ets.insert(:t, {1, 2})
      def c, do: Repo.insert(changeset)
      def d(raw), do: Jason.decode(raw)
    end
    """
    |> to_source_file("lib/forge/core/store.ex")
    |> run_check(PortProducerBoundary, boundaries())
    |> refute_issues()
  end

  test "issue: :os.cmd and System.shell are flagged outside a boundary" do
    triggers =
      """
      defmodule Forge.Core.Runner do
        def a, do: :os.cmd(~c"gh pr view")
        def b, do: System.shell("gh pr view")
      end
      """
      |> to_source_file("lib/forge/core/runner.ex")
      |> run_check(PortProducerBoundary, boundaries())
      |> Enum.map(& &1.trigger)
      |> Enum.sort()

    assert triggers == [":os.cmd", "System.shell"]
  end

  test "no issue: :os.cmd and System.shell inside a declared subprocess boundary" do
    """
    defmodule Forge.Ports.Gh do
      def a, do: :os.cmd(~c"gh pr view")
      def b, do: System.shell("gh pr view")
    end
    """
    |> to_source_file("lib/forge/ports/gh.ex")
    |> run_check(PortProducerBoundary, boundaries())
    |> refute_issues()
  end

  test "issue: Req bang variants are flagged outside a boundary" do
    triggers =
      """
      defmodule Forge.Core.Runner do
        def a(url), do: Req.get!(url)
        def b(url), do: Req.post!(url, json: %{})
        def c(url), do: Req.delete!(url)
      end
      """
      |> to_source_file("lib/forge/core/runner.ex")
      |> run_check(PortProducerBoundary, boundaries())
      |> Enum.map(& &1.trigger)
      |> Enum.sort()

    assert triggers == ["Req.delete!", "Req.get!", "Req.post!"]
  end

  test "no issue: Req.new is not flagged (it builds a request struct, no I/O)" do
    """
    defmodule Forge.Core.Client do
      def build(url), do: Req.new(base_url: url)
    end
    """
    |> to_source_file("lib/forge/core/client.ex")
    |> run_check(PortProducerBoundary, boundaries())
    |> refute_issues()
  end

  test "no issue: a function capture of a producer is a reference, not a call site" do
    """
    defmodule Forge.Core.Runner do
      def runner, do: &System.cmd/3
      def fetcher, do: &Req.get/1
    end
    """
    |> to_source_file("lib/forge/core/runner.ex")
    |> run_check(PortProducerBoundary, boundaries())
    |> refute_issues()
  end

  test "honors Credo's built-in `# credo:disable-for-next-line` escape hatch" do
    # The producer sits on line 4, directly below the disable comment on line 3.
    [issue] =
      """
      defmodule Forge.Core.Runner do
        def run(args) do
          # credo:disable-for-next-line ForgeCredoChecks.PortProducerBoundary
          System.cmd("gh", args)
        end
      end
      """
      |> to_source_file("lib/forge/core/runner.ex")
      |> run_check(PortProducerBoundary, boundaries())

    assert issue.line_no == 4

    # Credo applies the escape hatch centrally (outside the check) by matching a
    # `disable-for-next-line` comment against the issue one line below it. The
    # check's only job is to report the producer on its real line so the hatch
    # lands; this asserts the built-in filter suppresses exactly this issue.
    disable = ConfigComment.new("disable-for-next-line", "", 3)
    assert ConfigComment.ignores_issue?(disable, issue)
  end

  test "severity: exit_status is configurable for a soft (non-failing) rollout" do
    soft =
      """
      defmodule Forge.Core.Runner do
        def run(args), do: System.cmd("gh", args)
      end
      """
      |> to_source_file("lib/forge/core/runner.ex")
      |> run_check(PortProducerBoundary, boundaries(exit_status: 0))
      |> assert_issue()
      |> List.first()

    assert soft.exit_status == 0

    gate =
      """
      defmodule Forge.Core.Runner do
        def run(args), do: System.cmd("gh", args)
      end
      """
      |> to_source_file("lib/forge/core/runner.ex")
      |> run_check(PortProducerBoundary, boundaries())
      |> assert_issue()
      |> List.first()

    assert gate.exit_status != 0
  end
end
