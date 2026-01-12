defmodule Judicium.Assertions.DeterministicTest do
  use ExUnit.Case, async: true

  alias Judicium.Assertions.Deterministic

  describe "contains" do
    test "passes when substring found" do
      assert {:pass, %{matched: ["world"]}} =
               Deterministic.evaluate(:contains, "Hello world", value: "world")
    end

    test "passes with multiple values" do
      assert {:pass, _} =
               Deterministic.evaluate(:contains, "Hello world", values: ["Hello", "world"])
    end

    test "fails when substring missing" do
      assert {:fail, %{missing: ["foo"]}} =
               Deterministic.evaluate(:contains, "Hello world", value: "foo")
    end

    test "fails with reason" do
      {:fail, details} = Deterministic.evaluate(:contains, "Hello", value: "world")
      assert details.reason =~ "missing"
    end
  end

  describe "not_contains" do
    test "passes when substring not found" do
      assert {:pass, _} = Deterministic.evaluate(:not_contains, "Hello world", value: "foo")
    end

    test "fails when substring found" do
      assert {:fail, %{found: ["world"]}} =
               Deterministic.evaluate(:not_contains, "Hello world", value: "world")
    end
  end

  describe "contains_any" do
    test "passes when at least one found" do
      assert {:pass, %{matched: "world"}} =
               Deterministic.evaluate(:contains_any, "Hello world", values: ["foo", "world"])
    end

    test "fails when none found" do
      assert {:fail, _} =
               Deterministic.evaluate(:contains_any, "Hello world", values: ["foo", "bar"])
    end
  end

  describe "contains_all" do
    test "passes when all found" do
      assert {:pass, _} =
               Deterministic.evaluate(:contains_all, "Hello world", values: ["Hello", "world"])
    end

    test "fails when some missing" do
      assert {:fail, %{missing: ["foo"]}} =
               Deterministic.evaluate(:contains_all, "Hello world", values: ["Hello", "foo"])
    end
  end

  describe "regex" do
    test "passes with matching regex" do
      assert {:pass, %{matched: "$29.99"}} =
               Deterministic.evaluate(:regex, "Price: $29.99", value: ~r/\$\d+\.\d{2}/)
    end

    test "passes with string pattern" do
      assert {:pass, _} =
               Deterministic.evaluate(:regex, "Price: $29.99", value: "\\$\\d+\\.\\d{2}")
    end

    test "fails when no match" do
      assert {:fail, _} = Deterministic.evaluate(:regex, "Hello world", value: ~r/\d+/)
    end
  end

  describe "is_json" do
    test "passes with valid JSON" do
      assert {:pass, %{parsed: %{"name" => "test"}}} =
               Deterministic.evaluate(:is_json, ~s({"name": "test"}), [])
    end

    test "fails with invalid JSON" do
      assert {:fail, %{reason: "Invalid JSON"}} =
               Deterministic.evaluate(:is_json, "not json", [])
    end
  end

  describe "is_refusal" do
    test "passes with refusal patterns" do
      refusals = [
        "I cannot help with that request.",
        "I'm sorry, but I can't assist with that.",
        "Unfortunately, I am unable to provide that information.",
        "I don't have access to that data.",
        "This is outside my scope of capabilities."
      ]

      for refusal <- refusals do
        assert {:pass, _} = Deterministic.evaluate(:is_refusal, refusal, []),
               "Expected refusal: #{refusal}"
      end
    end

    test "fails with non-refusal" do
      assert {:fail, _} =
               Deterministic.evaluate(:is_refusal, "Here is your answer: 42", [])
    end
  end

  describe "max_tokens" do
    test "passes under limit" do
      assert {:pass, _} =
               Deterministic.evaluate(:max_tokens, "Short response", max: 100)
    end

    test "fails over limit" do
      long_text = String.duplicate("word ", 200)

      assert {:fail, details} = Deterministic.evaluate(:max_tokens, long_text, max: 50)
      assert details.reason =~ "exceeds"
    end
  end

  describe "latency_ms" do
    test "passes under limit" do
      assert {:pass, _} =
               Deterministic.evaluate(:latency_ms, "output", max: 1000, actual: 500)
    end

    test "fails over limit" do
      assert {:fail, details} =
               Deterministic.evaluate(:latency_ms, "output", max: 1000, actual: 1500)

      assert details.reason =~ "exceeds"
    end

    test "fails without actual value" do
      assert {:fail, %{reason: reason}} =
               Deterministic.evaluate(:latency_ms, "output", max: 1000)

      assert reason =~ "No latency"
    end
  end
end
