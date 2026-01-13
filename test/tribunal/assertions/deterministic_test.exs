defmodule Tribunal.Assertions.DeterministicTest do
  use ExUnit.Case, async: true

  alias Tribunal.Assertions.Deterministic

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

  describe "starts_with" do
    test "passes when output starts with value" do
      assert {:pass, %{prefix: "Hello"}} =
               Deterministic.evaluate(:starts_with, "Hello world", value: "Hello")
    end

    test "fails when output does not start with value" do
      assert {:fail, %{expected: "Goodbye"}} =
               Deterministic.evaluate(:starts_with, "Hello world", value: "Goodbye")
    end
  end

  describe "ends_with" do
    test "passes when output ends with value" do
      assert {:pass, %{suffix: "world"}} =
               Deterministic.evaluate(:ends_with, "Hello world", value: "world")
    end

    test "fails when output does not end with value" do
      assert {:fail, %{expected: "universe"}} =
               Deterministic.evaluate(:ends_with, "Hello world", value: "universe")
    end
  end

  describe "equals" do
    test "passes when output exactly matches" do
      assert {:pass, %{}} = Deterministic.evaluate(:equals, "exact match", value: "exact match")
    end

    test "fails when output differs" do
      assert {:fail, %{expected: "foo", actual: "bar"}} =
               Deterministic.evaluate(:equals, "bar", value: "foo")
    end
  end

  describe "min_length" do
    test "passes when output meets minimum length" do
      assert {:pass, %{length: 11, min: 5}} =
               Deterministic.evaluate(:min_length, "Hello world", value: 5)
    end

    test "fails when output is too short" do
      assert {:fail, %{length: 2, min: 10}} =
               Deterministic.evaluate(:min_length, "Hi", value: 10)
    end
  end

  describe "max_length" do
    test "passes when output is under max length" do
      assert {:pass, %{length: 11, max: 100}} =
               Deterministic.evaluate(:max_length, "Hello world", value: 100)
    end

    test "fails when output exceeds max length" do
      assert {:fail, %{length: 11, max: 5}} =
               Deterministic.evaluate(:max_length, "Hello world", value: 5)
    end
  end

  describe "word_count" do
    test "passes when word count is within range" do
      assert {:pass, %{word_count: 2}} =
               Deterministic.evaluate(:word_count, "Hello world", min: 1, max: 10)
    end

    test "fails when word count is below minimum" do
      assert {:fail, %{word_count: 1, min: 5}} =
               Deterministic.evaluate(:word_count, "Hello", min: 5)
    end

    test "fails when word count exceeds maximum" do
      assert {:fail, %{word_count: 5, max: 2}} =
               Deterministic.evaluate(:word_count, "one two three four five", max: 2)
    end
  end

  describe "is_url" do
    test "passes with valid URL" do
      assert {:pass, %{url: "https://example.com"}} =
               Deterministic.evaluate(:is_url, "https://example.com", [])
    end

    test "fails with invalid URL" do
      assert {:fail, %{reason: reason}} =
               Deterministic.evaluate(:is_url, "not a url at all", [])

      assert reason =~ "not a valid URL"
    end
  end

  describe "is_email" do
    test "passes with valid email" do
      assert {:pass, %{email: "test@example.com"}} =
               Deterministic.evaluate(:is_email, "test@example.com", [])
    end

    test "fails with invalid email" do
      assert {:fail, %{}} = Deterministic.evaluate(:is_email, "not-an-email", [])
    end
  end

  describe "levenshtein" do
    test "passes when edit distance is within threshold" do
      # "hello" vs "hallo" = 1 edit
      assert {:pass, %{distance: 1}} =
               Deterministic.evaluate(:levenshtein, "hallo", value: "hello", max_distance: 2)
    end

    test "fails when edit distance exceeds threshold" do
      assert {:fail, %{distance: distance, max_distance: 1}} =
               Deterministic.evaluate(:levenshtein, "completely different",
                 value: "hello",
                 max_distance: 1
               )

      assert distance > 1
    end
  end
end
