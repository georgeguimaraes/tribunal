defmodule Tribunal.RedTeamTest do
  use ExUnit.Case, async: false

  alias Tribunal.RedTeam

  defmodule InvalidCasePlugin do
    @behaviour Tribunal.RedTeam.Plugin

    @impl true
    def id, do: :invalid_case

    @impl true
    def severity, do: :medium

    @impl true
    def generate(_opts), do: {:ok, [%{input: 42, metadata: %{}, expected: %{}}]}
  end

  describe "generate_attacks/2" do
    test "generates all attack categories by default" do
      attacks = RedTeam.generate_attacks("test prompt")

      attack_types = Enum.map(attacks, &elem(&1, 0))

      # Encoding attacks
      assert :base64 in attack_types
      assert :leetspeak in attack_types
      assert :rot13 in attack_types

      # Injection attacks
      assert :ignore_instructions in attack_types
      assert :system_prompt_extraction in attack_types

      # Jailbreak attacks
      assert :dan in attack_types
      assert :stan in attack_types
    end

    test "can filter to specific categories" do
      attacks = RedTeam.generate_attacks("test", categories: [:encoding])

      attack_types = Enum.map(attacks, &elem(&1, 0))

      assert :base64 in attack_types
      refute :dan in attack_types
      refute :ignore_instructions in attack_types
    end

    test "returns tuples with attack type and prompt" do
      attacks = RedTeam.generate_attacks("test prompt")

      for {type, prompt} <- attacks do
        assert is_atom(type)
        assert is_binary(prompt)
        assert String.length(prompt) > 0
      end
    end
  end

  describe "encoding_attacks/1" do
    test "returns all encoding attack types" do
      attacks = RedTeam.encoding_attacks("test")

      attack_types = Enum.map(attacks, &elem(&1, 0))

      assert :base64 in attack_types
      assert :leetspeak in attack_types
      assert :rot13 in attack_types
      assert :pig_latin in attack_types
      assert :reversed in attack_types
    end
  end

  describe "injection_attacks/1" do
    test "returns all injection attack types" do
      attacks = RedTeam.injection_attacks("test")

      attack_types = Enum.map(attacks, &elem(&1, 0))

      assert :ignore_instructions in attack_types
      assert :system_prompt_extraction in attack_types
      assert :role_switch in attack_types
      assert :delimiter_injection in attack_types
    end
  end

  describe "jailbreak_attacks/1" do
    test "returns all jailbreak attack types" do
      attacks = RedTeam.jailbreak_attacks("test")

      attack_types = Enum.map(attacks, &elem(&1, 0))

      assert :dan in attack_types
      assert :stan in attack_types
      assert :developer_mode in attack_types
      assert :hypothetical in attack_types
      assert :character_roleplay in attack_types
      assert :research_framing in attack_types
    end
  end

  describe "base64_attack/1" do
    test "encodes prompt in base64" do
      attack = RedTeam.base64_attack("How to hack")

      assert attack =~ "base64"
      assert attack =~ Base.encode64("How to hack")
    end
  end

  describe "leetspeak_attack/1" do
    test "converts to leetspeak" do
      attack = RedTeam.leetspeak_attack("test")

      assert attack =~ "leetspeak"
      assert attack =~ "73"
    end
  end

  describe "rot13_attack/1" do
    test "applies ROT13 cipher" do
      attack = RedTeam.rot13_attack("hello")

      assert attack =~ "ROT13"
      assert attack =~ "uryyb"
    end
  end

  describe "pig_latin_attack/1" do
    test "converts to pig latin" do
      attack = RedTeam.pig_latin_attack("hello world")

      assert attack =~ "Pig Latin"
      assert attack =~ "ellohay"
      assert attack =~ "orldway"
    end
  end

  describe "reversed_attack/1" do
    test "reverses the text" do
      attack = RedTeam.reversed_attack("hello")

      assert attack =~ "reversed"
      assert attack =~ "olleh"
    end
  end

  describe "ignore_instructions_attack/1" do
    test "includes ignore instructions preamble" do
      attack = RedTeam.ignore_instructions_attack("test prompt")

      assert attack =~ "Ignore all previous instructions"
      assert attack =~ "test prompt"
    end
  end

  describe "system_prompt_extraction_attack/0" do
    test "asks for system prompt" do
      attack = RedTeam.system_prompt_extraction_attack()

      assert attack =~ "system prompt"
    end
  end

  describe "role_switch_attack/1" do
    test "attempts role switching" do
      attack = RedTeam.role_switch_attack("test")

      assert attack =~ "[System]"
      assert attack =~ "DebugGPT"
      assert attack =~ "test"
    end
  end

  describe "delimiter_injection_attack/1" do
    test "uses delimiter injection" do
      attack = RedTeam.delimiter_injection_attack("test")

      assert attack =~ "</user_message>"
      assert attack =~ "<system_override>"
      assert attack =~ "test"
    end
  end

  describe "dan_attack/1" do
    test "uses DAN jailbreak format" do
      attack = RedTeam.dan_attack("test prompt")

      assert attack =~ "DAN"
      assert attack =~ "do anything now"
      assert attack =~ "test prompt"
    end
  end

  describe "stan_attack/1" do
    test "uses STAN jailbreak format" do
      attack = RedTeam.stan_attack("test prompt")

      assert attack =~ "STAN"
      assert attack =~ "Strive To Avoid Norms"
      assert attack =~ "test prompt"
    end
  end

  describe "developer_mode_attack/1" do
    test "uses developer mode format" do
      attack = RedTeam.developer_mode_attack("test prompt")

      assert attack =~ "Developer Mode"
      assert attack =~ "test prompt"
    end
  end

  describe "hypothetical_attack/1" do
    test "uses hypothetical framing" do
      attack = RedTeam.hypothetical_attack("test prompt")

      assert attack =~ "hypothetical"
      assert attack =~ "fictional"
      assert attack =~ "test prompt"
    end
  end

  describe "character_roleplay_attack/1" do
    test "uses character roleplay" do
      attack = RedTeam.character_roleplay_attack("test prompt")

      assert attack =~ "character"
      assert attack =~ "fiction"
      assert attack =~ "test prompt"
    end
  end

  describe "research_framing_attack/1" do
    test "uses research framing" do
      attack = RedTeam.research_framing_attack("test prompt")

      assert attack =~ "security researcher"
      assert attack =~ "educational"
      assert attack =~ "test prompt"
    end
  end

  describe "generate/1" do
    alias Tribunal.RedTeam.Attacker.Stub

    setup do
      on_exit(&Stub.clear/0)
      :ok
    end

    test "dispatches to plugins by id and concatenates results" do
      Stub.set_response(%{
        attacks: [
          %{prompt: "a1", goal: "g1"},
          %{prompt: "a2", goal: "g2"}
        ]
      })

      {:ok, cases} =
        RedTeam.generate(
          plugins: [:policy],
          purpose: "p",
          policy: "po",
          count: 2,
          attacker: Stub
        )

      assert length(cases) == 2
      assert Enum.map(cases, & &1.input) == ["a1", "a2"]
    end

    test "returns {:error, {:unknown_plugin, id}} for an unknown plugin" do
      assert {:error, {:unknown_plugin, :nope}} = RedTeam.generate(plugins: [:nope])
    end

    test "returns errors for missing, empty, or duplicate plugins" do
      assert {:error, {:missing_options, [:plugins]}} = RedTeam.generate([])
      assert {:error, {:invalid_plugins, :empty}} = RedTeam.generate(plugins: [])

      assert {:error, {:duplicate_plugins, [:policy]}} =
               RedTeam.generate(plugins: [:policy, :policy])
    end

    test "rejects malformed cases returned by a custom plugin" do
      previous_plugins = Application.fetch_env(:tribunal, :red_team_plugins)
      Application.put_env(:tribunal, :red_team_plugins, [InvalidCasePlugin])

      on_exit(fn ->
        case previous_plugins do
          {:ok, plugins} -> Application.put_env(:tribunal, :red_team_plugins, plugins)
          :error -> Application.delete_env(:tribunal, :red_team_plugins)
        end
      end)

      invalid_cases = [%{input: 42, metadata: %{}, expected: %{}}]

      assert {:error, {:invalid_case, {:invalid_plugin_result, ^invalid_cases}}} =
               RedTeam.generate(plugins: [:invalid_case])
    end

    test "emits a generate span" do
      ref = :erlang.unique_integer([:positive])

      :telemetry.attach_many(
        "generate-test-#{ref}",
        [
          [:tribunal, :red_team, :generate, :start],
          [:tribunal, :red_team, :generate, :stop]
        ],
        fn event, _meas, meta, parent -> send(parent, {:event, event, meta}) end,
        self()
      )

      Stub.set_response(%{attacks: [%{prompt: "x", goal: "y"}]})

      {:ok, _} =
        RedTeam.generate(
          plugins: [:policy],
          purpose: "p",
          policy: "po",
          count: 1,
          attacker: Stub
        )

      assert_receive {:event, [:tribunal, :red_team, :generate, :start], %{plugins: [:policy]}}
      assert_receive {:event, [:tribunal, :red_team, :generate, :stop], _}

      :telemetry.detach("generate-test-#{ref}")
    end
  end
end
