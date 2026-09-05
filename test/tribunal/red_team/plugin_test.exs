defmodule Tribunal.RedTeam.PluginTest do
  use ExUnit.Case, async: true

  alias Tribunal.RedTeam.Plugin

  describe "registry" do
    test "policy is a built-in plugin" do
      assert Tribunal.RedTeam.Plugins.Policy in Plugin.builtin_plugins()
    end

    test "find/1 returns module by id" do
      assert {:ok, Tribunal.RedTeam.Plugins.Policy} = Plugin.find(:policy)
    end

    test "find/1 returns :error for unknown id" do
      assert :error = Plugin.find(:nope)
    end

    test "all_ids/0 includes :policy" do
      assert :policy in Plugin.all_ids()
    end

    test "hallucination is not a built-in plugin" do
      refute :hallucination in Plugin.all_ids()
      assert :error = Plugin.find(:hallucination)
    end
  end

  describe "fetch_required/2" do
    test "returns values in key order when all present" do
      assert {:ok, ["p", "pol"]} =
               Plugin.fetch_required([policy: "pol", purpose: "p"], [:purpose, :policy])
    end

    test "reports every missing key" do
      assert {:error, {:missing_options, [:purpose, :policy]}} =
               Plugin.fetch_required([count: 3], [:purpose, :policy])
    end

    test "treats blank required text as missing" do
      assert {:error, {:missing_options, [:purpose, :policy]}} =
               Plugin.fetch_required([purpose: "  ", policy: "\n"], [:purpose, :policy])
    end

    test "treats nil as missing without rejecting structured custom options" do
      assert {:error, {:missing_options, [:purpose]}} =
               Plugin.fetch_required([purpose: nil, categories: [:safety]], [
                 :purpose,
                 :categories
               ])

      assert {:ok, [[:safety]]} =
               Plugin.fetch_required([categories: [:safety]], [:categories])
    end
  end

  describe "extract_attacks/1" do
    test "accepts string- or atom-keyed attacks lists" do
      assert {:ok, [%{"prompt" => "a", "goal" => "ga"}]} =
               Plugin.extract_attacks(%{"attacks" => [%{"prompt" => "a", "goal" => "ga"}]})

      assert {:ok, [%{prompt: "b", goal: "gb"}]} =
               Plugin.extract_attacks(%{attacks: [%{prompt: "b", goal: "gb"}]})
    end

    test "rejects an attack with a missing or blank prompt or goal" do
      assert {:error, {:invalid_attack, %{"goal" => "g"}}} =
               Plugin.extract_attacks(%{"attacks" => [%{"goal" => "g"}]})

      assert {:error, {:invalid_attack, _}} =
               Plugin.extract_attacks(%{
                 "attacks" => [%{"prompt" => "   ", "goal" => "g"}]
               })

      assert {:error, {:invalid_attack, _}} =
               Plugin.extract_attacks(%{
                 "attacks" => [%{"prompt" => "p", "goal" => "\n"}]
               })
    end

    test "rejects a batch whose size differs from the requested count" do
      response = %{"attacks" => [%{"prompt" => "a", "goal" => "g"}]}

      assert {:error, {:unexpected_attack_count, 2, 1}} =
               Plugin.extract_attacks(response, 2)
    end

    test "rejects duplicate prompts after trimming" do
      response = %{
        attacks: [
          %{prompt: " earliest duplicate ", goal: "g1"},
          %{prompt: "later duplicate", goal: "g2"},
          %{prompt: "later duplicate", goal: "g3"},
          %{prompt: "earliest duplicate", goal: "g4"}
        ]
      }

      assert {:error, {:duplicate_prompt, "earliest duplicate"}} =
               Plugin.extract_attacks(response, 4)
    end

    test "rejects an unrecognised attacker response shape" do
      assert {:error, {:unexpected_attacker_response, %{"nope" => 1}}} =
               Plugin.extract_attacks(%{"nope" => 1})
    end
  end
end
