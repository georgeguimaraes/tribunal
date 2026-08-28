defmodule Mix.Tasks.TribunalRedteamGenerateTest do
  use ExUnit.Case, async: false

  alias Mix.Tasks.Tribunal.Redteam.Generate

  test "rejects unknown plugins without creating atoms" do
    plugin = "unknown_#{System.unique_integer([:positive])}"
    refute existing_atom?(plugin)

    assert_raise Mix.Error, ~r/Unknown red-team plugin/, fn ->
      Generate.run(["--plugins", plugin, "--purpose", "test"])
    end

    refute existing_atom?(plugin)
  end

  defp existing_atom?(value) do
    _atom = String.to_existing_atom(value)
    true
  rescue
    ArgumentError -> false
  end
end
