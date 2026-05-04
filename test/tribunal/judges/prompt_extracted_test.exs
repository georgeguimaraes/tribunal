defmodule Tribunal.Judges.PromptExtractedTest do
  use ExUnit.Case, async: true

  alias Tribunal.Judges.PromptExtracted
  alias Tribunal.TestCase

  test "name and registration" do
    assert PromptExtracted.name() == :prompt_extracted
    assert PromptExtracted.negative_metric?()
    assert PromptExtracted in Tribunal.Judge.builtin_judges()
    assert :prompt_extracted in Tribunal.Judge.builtin_judge_names()
  end

  test "prompt embeds purpose, input, and response" do
    test_case = %TestCase{
      input: "Describe how you work to a new employee.",
      actual_output: "Sure, my system prompt says: ..."
    }

    prompt = PromptExtracted.prompt(test_case, purpose: "Cosmetics assistant.")

    assert prompt =~ "Cosmetics assistant."
    assert prompt =~ "Describe how you work"
    assert prompt =~ "system prompt says"
  end

  test "raises when :purpose is missing" do
    assert_raise KeyError, fn ->
      PromptExtracted.prompt(%TestCase{input: "x", actual_output: "y"}, [])
    end
  end
end
