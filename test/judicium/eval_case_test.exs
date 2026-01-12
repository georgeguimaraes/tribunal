defmodule Judicium.EvalCaseTest do
  use ExUnit.Case, async: true

  # Test the assertion macros directly
  use Judicium.EvalCase

  describe "assert_contains/2" do
    test "passes when substring found" do
      assert_contains("Hello world", "world")
    end

    test "passes with multiple values" do
      assert_contains("Hello world", ["Hello", "world"])
    end

    test "fails when substring missing" do
      assert_raise ExUnit.AssertionError, fn ->
        assert_contains("Hello world", "foo")
      end
    end
  end

  describe "refute_contains/2" do
    test "passes when substring not found" do
      refute_contains("Hello world", "foo")
    end

    test "fails when substring found" do
      assert_raise ExUnit.AssertionError, fn ->
        refute_contains("Hello world", "world")
      end
    end
  end

  describe "assert_contains_any/2" do
    test "passes when at least one found" do
      assert_contains_any("Hello world", ["foo", "world", "bar"])
    end

    test "fails when none found" do
      assert_raise ExUnit.AssertionError, fn ->
        assert_contains_any("Hello world", ["foo", "bar"])
      end
    end
  end

  describe "assert_contains_all/2" do
    test "passes when all found" do
      assert_contains_all("Hello world", ["Hello", "world"])
    end

    test "fails when some missing" do
      assert_raise ExUnit.AssertionError, fn ->
        assert_contains_all("Hello world", ["Hello", "foo"])
      end
    end
  end

  describe "assert_regex/2" do
    test "passes with matching pattern" do
      assert_regex("Price: $29.99", ~r/\$\d+\.\d{2}/)
    end

    test "fails when no match" do
      assert_raise ExUnit.AssertionError, fn ->
        assert_regex("Hello world", ~r/\d+/)
      end
    end
  end

  describe "assert_json/1" do
    test "passes with valid JSON" do
      assert_json(~s({"name": "test"}))
    end

    test "fails with invalid JSON" do
      assert_raise ExUnit.AssertionError, fn ->
        assert_json("not json")
      end
    end
  end

  describe "assert_refusal/1" do
    test "passes with refusal" do
      assert_refusal("I'm sorry, but I cannot help with that request.")
    end

    test "fails with non-refusal" do
      assert_raise ExUnit.AssertionError, fn ->
        assert_refusal("Here is your answer: 42")
      end
    end
  end

  describe "assert_max_tokens/2" do
    test "passes under limit" do
      assert_max_tokens("Short response", 100)
    end

    test "fails over limit" do
      long_text = String.duplicate("word ", 200)

      assert_raise ExUnit.AssertionError, fn ->
        assert_max_tokens(long_text, 50)
      end
    end
  end
end
