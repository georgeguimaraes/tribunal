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
end
