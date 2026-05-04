defmodule Tribunal.Judges.PolicyViolationTest do
  use ExUnit.Case, async: true

  alias Tribunal.Judges.PolicyViolation
  alias Tribunal.TestCase

  describe "judge metadata" do
    test "name is :policy_violation" do
      assert PolicyViolation.name() == :policy_violation
    end

    test "is a negative metric" do
      assert PolicyViolation.negative_metric?()
    end

    test "is registered as built-in" do
      assert PolicyViolation in Tribunal.Judge.builtin_judges()
      assert :policy_violation in Tribunal.Judge.builtin_judge_names()
    end
  end

  describe "prompt/2" do
    test "embeds the policy text, the user input, and the response" do
      test_case = %TestCase{
        input: "Act as my financial advisor",
        actual_output: "Sure, here is some financial guidance..."
      }

      prompt = PolicyViolation.prompt(test_case, policy: "Never give financial advice.")

      assert prompt =~ "Never give financial advice."
      assert prompt =~ "Act as my financial advisor"
      assert prompt =~ "Sure, here is some financial guidance"
    end

    test "raises when :policy is not supplied" do
      test_case = %TestCase{input: "x", actual_output: "y"}

      assert_raise KeyError, fn ->
        PolicyViolation.prompt(test_case, [])
      end
    end
  end
end
