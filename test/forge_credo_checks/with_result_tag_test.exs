defmodule ForgeCredoChecks.WithResultTagTest do
  use Credo.Test.Case

  alias ForgeCredoChecks.WithResultTag

  test "no issue: bare :ok and :error tags allowed by default" do
    """
    defmodule Sample do
      def go(id) do
        with :ok <- authorize(id),
             :error <- maybe_warn(id) do
          :done
        end
      end
    end
    """
    |> to_source_file()
    |> run_check(WithResultTag)
    |> refute_issues()
  end

  test "no issue: tagged tuples with :ok or :error" do
    """
    defmodule Sample do
      def go(id) do
        with {:ok, user} <- find(id),
             {:error, _reason} <- audit(user) do
          {:ok, user}
        end
      end
    end
    """
    |> to_source_file()
    |> run_check(WithResultTag)
    |> refute_issues()
  end

  test "no issue: variables, struct matches, list patterns are skipped" do
    """
    defmodule Sample do
      def go(id) do
        with %User{} = user <- find(id),
             [_ | _] = roles <- list_roles(user),
             ^id <- check(user) do
          {:ok, user, roles}
        end
      end
    end
    """
    |> to_source_file()
    |> run_check(WithResultTag)
    |> refute_issues()
  end

  test "issue: bare atom not in allowlist" do
    """
    defmodule Sample do
      def go(id) do
        with :loaded <- preload(id) do
          :done
        end
      end
    end
    """
    |> to_source_file()
    |> run_check(WithResultTag)
    |> assert_issue()
  end

  test "issue: tagged tuple with non-allowed tag" do
    """
    defmodule Sample do
      def go(id) do
        with {:found, user} <- lookup(id) do
          {:ok, user}
        end
      end
    end
    """
    |> to_source_file()
    |> run_check(WithResultTag)
    |> assert_issue()
  end

  test "issue: 3-tuple with non-allowed tag" do
    """
    defmodule Sample do
      def go(id) do
        with {:retry, attempt, delay} <- schedule(id) do
          {:ok, attempt, delay}
        end
      end
    end
    """
    |> to_source_file()
    |> run_check(WithResultTag)
    |> assert_issue()
  end

  test "configurable: extending allowlist accepts custom atoms" do
    """
    defmodule Sample do
      def go(id) do
        with {:found, user} <- lookup(id),
             :loaded <- preload(user) do
          {:ok, user}
        end
      end
    end
    """
    |> to_source_file()
    |> run_check(WithResultTag, allowed_atoms: [:ok, :error, :found, :loaded])
    |> refute_issues()
  end

  test "configurable: empty allowlist flags every atom-tagged clause" do
    """
    defmodule Sample do
      def go(id) do
        with {:ok, user} <- find(id),
             :ok <- authorize(user) do
          {:ok, user}
        end
      end
    end
    """
    |> to_source_file()
    |> run_check(WithResultTag, allowed_atoms: [])
    |> assert_issues(fn issues -> assert length(issues) == 2 end)
  end
end
