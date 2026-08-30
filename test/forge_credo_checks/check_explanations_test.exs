defmodule ForgeCredoChecks.CheckExplanationsTest do
  @moduledoc false

  use ExUnit.Case, async: true

  # `use Credo.Check` calls `Credo.Check.__build_moduledoc__/0`, which OVERWRITES
  # `@moduledoc`. Prose written as a hand-rolled `@moduledoc` in a check module is
  # discarded: it reaches neither hexdocs nor `mix credo explain`. Only
  # `explanations[:check]` is rendered. These tests assert the guidance an agent
  # actually receives is present in the rendered documentation.
  @documented_checks [
    ForgeCredoChecks.MimicCopyOutsideRegistry,
    ForgeCredoChecks.NoDetsInfoOpenGuard,
    ForgeCredoChecks.NoGlobalPubSubWildcardRefute,
    ForgeCredoChecks.NoTelemetryAssertionsInTest,
    ForgeCredoChecks.TimingAndPrivateStateGuard
  ]

  for check <- @documented_checks do
    test "#{inspect(check)} renders its guidance, including Bad and Good examples" do
      doc = rendered_moduledoc(unquote(check))

      assert doc =~ "## Why"
      assert doc =~ "## Bad"
      assert doc =~ "## Good"
    end
  end

  test "NoDetsInfoOpenGuard explains the dets_server registration hazard" do
    doc = rendered_moduledoc(ForgeCredoChecks.NoDetsInfoOpenGuard)

    assert doc =~ "dets_server"
    assert doc =~ "already_started"
  end

  test "NoTelemetryAssertionsInTest rules out deleting the attachment" do
    doc = rendered_moduledoc(ForgeCredoChecks.NoTelemetryAssertionsInTest)

    assert doc =~ "The fix is not deletion"
    assert doc =~ "Phoenix.PubSub"
  end

  test "TimingAndPrivateStateGuard names alternatives and rules out a test-only clause" do
    doc = rendered_moduledoc(ForgeCredoChecks.TimingAndPrivateStateGuard)

    assert doc =~ "Process.monitor"
    assert doc =~ "assert_receive"
    assert doc =~ "__test_state__"
  end

  test "no check module carries a project-specific Symphony contract path" do
    Enum.each(@documented_checks, fn check ->
      refute rendered_moduledoc(check) =~ "template_variables_contract_test"
    end)
  end

  defp rendered_moduledoc(check) do
    assert {:docs_v1, _anno, _lang, _format, %{"en" => doc}, _meta, _docs} =
             Code.fetch_docs(check)

    doc
  end
end
