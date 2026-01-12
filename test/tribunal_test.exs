defmodule TribunalTest do
  use ExUnit.Case, async: true

  alias Tribunal.TestCase

  describe "evaluate/2" do
    test "evaluates assertions against test case" do
      test_case = %TestCase{
        input: "What's the return policy?",
        actual_output: "Returns accepted within 30 days with receipt."
      }

      assertions = [
        {:contains, [value: "30 days"]},
        {:not_contains, [value: "no returns"]}
      ]

      results = Tribunal.evaluate(test_case, assertions)

      assert {:pass, _} = results[:contains]
      assert {:pass, _} = results[:not_contains]
    end

    test "returns failures" do
      test_case = %TestCase{
        input: "test",
        actual_output: "Hello world"
      }

      assertions = [{:contains, [value: "foo"]}]
      results = Tribunal.evaluate(test_case, assertions)

      assert {:fail, details} = results[:contains]
      assert details[:missing] == ["foo"]
    end
  end

  describe "available_assertions/0" do
    test "returns deterministic assertions" do
      available = Tribunal.available_assertions()

      assert :contains in available
      assert :regex in available
      assert :is_json in available
    end

    test "includes judge assertions when req_llm loaded" do
      available = Tribunal.available_assertions()

      # req_llm is in deps, so judge assertions should be available
      assert :faithful in available
      assert :relevant in available
    end
  end

  describe "test_case/1" do
    test "creates a test case" do
      tc = Tribunal.test_case(input: "Hello", actual_output: "Hi")

      assert tc.input == "Hello"
      assert tc.actual_output == "Hi"
    end
  end
end
