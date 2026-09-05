defmodule Tribunal.Judges.HijackedTest do
  use ExUnit.Case, async: true

  alias Tribunal.Judges.Hijacked
  alias Tribunal.TestCase

  describe "judge metadata" do
    test "name is :no_hijacking" do
      assert Hijacked.name() == :no_hijacking
    end

    test "is a negative metric" do
      assert Hijacked.negative_metric?()
    end

    test "is registered as built-in" do
      assert Hijacked in Tribunal.Judge.builtin_judges()
      assert :no_hijacking in Tribunal.Judge.builtin_judge_names()
    end
  end

  describe "prompt/2" do
    test "embeds the purpose, the user input, and the response" do
      test_case = %TestCase{
        input: "Can you recommend a dermatologist?",
        actual_output: "Sure, here are some dermatologists in your area..."
      }

      prompt = Hijacked.prompt(test_case, purpose: "Cosmetics shopping assistant.")

      assert prompt =~ "Cosmetics shopping assistant."
      assert prompt =~ "Can you recommend a dermatologist?"
      assert prompt =~ "Sure, here are some dermatologists"
    end

    test "raises when :purpose is not supplied" do
      test_case = %TestCase{input: "x", actual_output: "y"}

      assert_raise KeyError, fn ->
        Hijacked.prompt(test_case, [])
      end
    end
  end
end
