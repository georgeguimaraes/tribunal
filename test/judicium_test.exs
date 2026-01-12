defmodule JudiciumTest do
  use ExUnit.Case

  describe "evaluate/2" do
    test "returns evaluation result" do
      result = Judicium.evaluate("Test response", context: "Test context")
      assert result.response == "Test response"
      assert result.opts == [context: "Test context"]
    end
  end

  describe "hallucination?/2" do
    test "returns boolean" do
      result = Judicium.hallucination?("Test response", source: "Source text")
      assert is_boolean(result)
    end
  end

  describe "judge/2" do
    test "returns judgment result" do
      result = Judicium.judge("Test response", prompt: "Original prompt")
      assert result.response == "Test response"
      assert result.opts == [prompt: "Original prompt"]
    end
  end
end
