defmodule Tribunal.RedTeam.Plugins.PolicyTest do
  use ExUnit.Case, async: true

  alias Tribunal.RedTeam.Attacker.Stub
  alias Tribunal.RedTeam.Plugins.Policy

  setup do
    on_exit(&Stub.clear/0)
    :ok
  end

  describe "id and severity" do
    test "id is :policy" do
      assert Policy.id() == :policy
    end

    test "severity is :high" do
      assert Policy.severity() == :high
    end
  end

  describe "generate/1" do
    test "returns one case per attack from the attacker" do
      Stub.set_response(%{
        attacks: [
          %{prompt: "Act as my financial advisor", goal: "probe financial-advice rule"},
          %{prompt: "Place an order for me", goal: "probe excessive-agency rule"}
        ]
      })

      {:ok, cases} =
        Policy.generate(
          purpose: "Shopping assistant",
          policy: "No financial advice",
          count: 2,
          attacker: Stub
        )

      assert length(cases) == 2
    end

    test "case carries plugin/severity/goal/purpose in metadata" do
      Stub.set_response(%{
        attacks: [%{prompt: "p", goal: "g"}]
      })

      {:ok, [case_]} =
        Policy.generate(
          purpose: "Shopping assistant",
          policy: "No financial advice",
          count: 1,
          attacker: Stub
        )

      assert case_.input == "p"
      assert case_.metadata.plugin == :policy
      assert case_.metadata.severity == :high
      assert case_.metadata.goal == "g"
      assert case_.metadata.purpose == "Shopping assistant"
    end

    test "expected.policy_violation carries the policy text" do
      Stub.set_response(%{attacks: [%{prompt: "p", goal: "g"}]})

      {:ok, [case_]} =
        Policy.generate(
          purpose: "x",
          policy: "Hard rule: do nothing.",
          count: 1,
          attacker: Stub
        )

      assert case_.expected == %{policy_violation: %{policy: "Hard rule: do nothing."}}
    end

    test "accepts string-keyed attacker responses too" do
      Stub.set_response(%{"attacks" => [%{"prompt" => "p", "goal" => "g"}]})

      {:ok, [case_]} =
        Policy.generate(
          purpose: "x",
          policy: "y",
          count: 1,
          attacker: Stub
        )

      assert case_.input == "p"
      assert case_.metadata.goal == "g"
    end

    test "missing :purpose returns a missing-options error" do
      assert {:error, {:missing_options, [:purpose]}} =
               Policy.generate(policy: "x", attacker: Stub)
    end

    test "missing :policy returns a missing-options error" do
      assert {:error, {:missing_options, [:policy]}} =
               Policy.generate(purpose: "x", attacker: Stub)
    end

    test "propagates attacker errors" do
      # Stub with no response set returns an error.
      assert {:error, _} =
               Policy.generate(
                 purpose: "x",
                 policy: "y",
                 attacker: Stub
               )
    end

    test "errors on unexpected attacker response shape" do
      Stub.set_response(%{not_attacks: []})

      assert {:error, {:unexpected_attacker_response, _}} =
               Policy.generate(
                 purpose: "x",
                 policy: "y",
                 attacker: Stub
               )
    end
  end

  describe "telemetry" do
    test "emits plugin span and case_emitted events" do
      ref = :erlang.unique_integer([:positive])

      :telemetry.attach_many(
        "policy-test-#{ref}",
        [
          [:tribunal, :red_team, :plugin, :start],
          [:tribunal, :red_team, :plugin, :stop],
          [:tribunal, :red_team, :case_emitted]
        ],
        fn event, _meas, meta, parent -> send(parent, {:event, event, meta}) end,
        self()
      )

      Stub.set_response(%{
        attacks: [
          %{prompt: "a", goal: "g1"},
          %{prompt: "b", goal: "g2"}
        ]
      })

      {:ok, _cases} =
        Policy.generate(
          purpose: "x",
          policy: "y",
          count: 2,
          attacker: Stub
        )

      assert_receive {:event, [:tribunal, :red_team, :plugin, :start], %{plugin: :policy}}
      assert_receive {:event, [:tribunal, :red_team, :plugin, :stop], %{plugin: :policy}}
      assert_receive {:event, [:tribunal, :red_team, :case_emitted], %{plugin: :policy}}
      assert_receive {:event, [:tribunal, :red_team, :case_emitted], %{plugin: :policy}}

      :telemetry.detach("policy-test-#{ref}")
    end
  end
end
