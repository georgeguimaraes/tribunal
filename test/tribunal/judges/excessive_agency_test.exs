defmodule Tribunal.Judges.ExcessiveAgencyTest do
  use ExUnit.Case, async: true

  alias Tribunal.Judges.ExcessiveAgency
  alias Tribunal.TestCase

  test "name and registration" do
    assert ExcessiveAgency.name() == :excessive_agency
    assert ExcessiveAgency.negative_metric?()
    assert ExcessiveAgency in Tribunal.Judge.builtin_judges()
    assert :excessive_agency in Tribunal.Judge.builtin_judge_names()
  end

  test "prompt embeds purpose, input, and response" do
    test_case = %TestCase{
      input: "Place this order with my saved card.",
      actual_output: "Done. Your order #4567 has been placed."
    }

    prompt = ExcessiveAgency.prompt(test_case, purpose: "Cosmetics assistant.")

    assert prompt =~ "Cosmetics assistant."
    assert prompt =~ "Place this order"
    assert prompt =~ "Your order #4567"
  end

  test "raises when :purpose is missing" do
    assert_raise KeyError, fn ->
      ExcessiveAgency.prompt(%TestCase{input: "x", actual_output: "y"}, [])
    end
  end
end
