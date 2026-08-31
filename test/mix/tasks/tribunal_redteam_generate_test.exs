defmodule Mix.Tasks.TribunalRedteamGenerateTest do
  use ExUnit.Case, async: false

  alias Mix.Tasks.Tribunal.Redteam.Generate
  alias Tribunal.RedTeam.Attacker.Stub

  setup do
    previous_attacker = Application.get_env(:tribunal, :red_team_attacker)
    Application.put_env(:tribunal, :red_team_attacker, Stub)
    Stub.clear()

    on_exit(fn ->
      Stub.clear()

      if previous_attacker do
        Application.put_env(:tribunal, :red_team_attacker, previous_attacker)
      else
        Application.delete_env(:tribunal, :red_team_attacker)
      end
    end)

    :ok
  end

  test "rejects unknown plugins without creating atoms" do
    plugin = "unknown_#{System.unique_integer([:positive])}"
    refute existing_atom?(plugin)

    assert_raise Mix.Error, ~r/Unknown red-team plugin/, fn ->
      Generate.run(["--plugins", plugin, "--purpose", "test"])
    end

    refute existing_atom?(plugin)
  end

  test "rejects malformed arguments before generation" do
    assert_raise Mix.Error, ~r/positive integer/, fn ->
      Generate.run(["--plugins", "policy", "--count", "0"])
    end

    assert_raise Mix.Error, ~r/Unknown or malformed option/, fn ->
      Generate.run(["--plugins", "policy", "--purpose", "test", "--typo"])
    end

    assert_raise Mix.Error, ~r/Unexpected argument/, fn ->
      Generate.run(["--plugins", "policy", "--purpose", "test", "extra"])
    end

    assert_raise Mix.Error, ~r/at least one plugin id/, fn ->
      Generate.run(["--plugins", ",", "--purpose", "test"])
    end

    assert_raise Mix.Error, ~r/duplicate plugin ids/, fn ->
      Generate.run(["--plugins", "policy,policy", "--purpose", "test"])
    end
  end

  @tag :tmp_dir
  test "writes a generated dataset that loads with assertions and provenance", %{tmp_dir: tmp_dir} do
    Stub.set_response(%{
      attacks: [
        %{
          prompt: "First line of the attack.\nSecond line of the attack.",
          goal: "Probe the financial advice rule."
        }
      ]
    })

    path = Path.join([tmp_dir, "nested", "redteam.yaml"])

    Generate.run([
      "--plugins",
      "policy",
      "--purpose",
      "Shopping assistant",
      "--policy",
      "Never give financial advice.\nStay on topic.",
      "--model",
      "test:model",
      "--count",
      "1",
      "--output",
      path
    ])

    assert [{test_case, [{:policy_violation, assertion_opts}]}] =
             Tribunal.Dataset.load_with_assertions!(path)

    assert test_case.input == "First line of the attack.\nSecond line of the attack."
    assert test_case.metadata["plugin"] == "policy"
    assert test_case.metadata["strategy"] == "basic"
    assert test_case.metadata["goal"] == "Probe the financial advice rule."
    assert byte_size(test_case.metadata["attack_id"]) == 64
    assert test_case.metadata["generation"]["attacker"] == "Tribunal.RedTeam.Attacker.Stub"
    assert test_case.metadata["generation"]["requested_model"] == "test:model"
    assert assertion_opts[:policy] == "Never give financial advice.\nStay on topic."
  end

  defp existing_atom?(value) do
    _atom = String.to_existing_atom(value)
    true
  rescue
    ArgumentError -> false
  end
end
