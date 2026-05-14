defmodule ForgeCredoChecks.NoKernelOpInPipelineTest do
  use Credo.Test.Case

  alias ForgeCredoChecks.NoKernelOpInPipeline

  test "no issue: infix operator outside a pipe" do
    """
    defmodule Sample do
      def f(a, b) do
        a == b
      end
    end
    """
    |> to_source_file()
    |> run_check(NoKernelOpInPipeline)
    |> refute_issues()
  end

  test "no issue: pipe into a regular function" do
    """
    defmodule Sample do
      def f(list) do
        list |> Enum.uniq() |> Enum.sort()
      end
    end
    """
    |> to_source_file()
    |> run_check(NoKernelOpInPipeline)
    |> refute_issues()
  end

  test "no issue: arithmetic operators in pipelines are allowed" do
    """
    defmodule Sample do
      def f(n) do
        n |> Kernel.+(1)
      end
    end
    """
    |> to_source_file()
    |> run_check(NoKernelOpInPipeline)
    |> refute_issues()
  end

  test "issue: pipe into Kernel.==" do
    """
    defmodule Sample do
      def f(list, other) do
        list |> Enum.sort() |> Kernel.==(other)
      end
    end
    """
    |> to_source_file()
    |> run_check(NoKernelOpInPipeline)
    |> assert_issue()
  end

  test "issue: pipe into Kernel.>=" do
    """
    defmodule Sample do
      def f(score, threshold) do
        score |> calculate() |> Kernel.>=(threshold)
      end
    end
    """
    |> to_source_file()
    |> run_check(NoKernelOpInPipeline)
    |> assert_issue()
  end

  test "issue: pipe into Kernel.and" do
    """
    defmodule Sample do
      def f(x, y) do
        x |> truthy?() |> Kernel.and(y)
      end
    end
    """
    |> to_source_file()
    |> run_check(NoKernelOpInPipeline)
    |> assert_issue()
  end
end
