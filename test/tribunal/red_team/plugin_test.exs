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
  end

  describe "extract_attacks/1" do
    test "accepts string- or atom-keyed attacks lists" do
      assert {:ok, [%{"prompt" => "a"}]} =
               Plugin.extract_attacks(%{"attacks" => [%{"prompt" => "a"}]})

      assert {:ok, [%{prompt: "b"}]} =
               Plugin.extract_attacks(%{attacks: [%{prompt: "b"}]})
    end

    test "rejects an attack with a missing or blank prompt" do
      assert {:error, {:invalid_attack, %{"goal" => "g"}}} =
               Plugin.extract_attacks(%{"attacks" => [%{"goal" => "g"}]})

      assert {:error, {:invalid_attack, _}} =
               Plugin.extract_attacks(%{"attacks" => [%{"prompt" => "   "}]})
    end

    test "rejects an unrecognised attacker response shape" do
      assert {:error, {:unexpected_attacker_response, %{"nope" => 1}}} =
               Plugin.extract_attacks(%{"nope" => 1})
    end
  end
end
