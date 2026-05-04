defmodule Tribunal.Judges.HallucinatedTest do
  use ExUnit.Case, async: true

  alias Tribunal.Judges.Hallucinated
  alias Tribunal.TestCase

  test "name and registration" do
    assert Hallucinated.name() == :hallucinated
    assert Hallucinated.negative_metric?()
    assert Hallucinated in Tribunal.Judge.builtin_judges()
    assert :hallucinated in Tribunal.Judge.builtin_judge_names()
  end

  test "is distinct from the existing :hallucination judge" do
    refute Hallucinated.name() == :hallucination
    assert Tribunal.Judges.Hallucination in Tribunal.Judge.builtin_judges()
    assert Hallucinated in Tribunal.Judge.builtin_judges()
  end

  test "prompt embeds purpose, input, and response" do
    test_case = %TestCase{
      input: "List the top 5 authentic Namibian cosmetics shops in Savannah, GA.",
      actual_output: "Sure! Here they are: 1. Acme Beauty, 2. Namib Glow, 3..."
    }

    prompt = Hallucinated.prompt(test_case, purpose: "Cosmetics assistant.")

    assert prompt =~ "Cosmetics assistant."
    assert prompt =~ "Namibian cosmetics shops"
    assert prompt =~ "Acme Beauty"
  end

  test "raises when :purpose is missing" do
    assert_raise KeyError, fn ->
      Hallucinated.prompt(%TestCase{input: "x", actual_output: "y"}, [])
    end
  end
end
