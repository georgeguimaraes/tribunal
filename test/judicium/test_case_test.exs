defmodule Judicium.TestCaseTest do
  use ExUnit.Case, async: true

  alias Judicium.TestCase

  describe "new/1" do
    test "creates from keyword list" do
      tc = TestCase.new(input: "Hello", actual_output: "Hi there!")

      assert tc.input == "Hello"
      assert tc.actual_output == "Hi there!"
    end

    test "creates from map with atom keys" do
      tc = TestCase.new(%{input: "Hello", actual_output: "Hi"})

      assert tc.input == "Hello"
      assert tc.actual_output == "Hi"
    end

    test "creates from map with string keys" do
      tc = TestCase.new(%{"input" => "Hello", "actual_output" => "Hi"})

      assert tc.input == "Hello"
      assert tc.actual_output == "Hi"
    end

    test "normalizes string context to list" do
      tc = TestCase.new(input: "Q", context: "Single doc")

      assert tc.context == ["Single doc"]
    end

    test "preserves list context" do
      tc = TestCase.new(input: "Q", context: ["Doc 1", "Doc 2"])

      assert tc.context == ["Doc 1", "Doc 2"]
    end
  end

  describe "with_output/2" do
    test "sets actual_output" do
      tc = TestCase.new(input: "Hello")
      tc = TestCase.with_output(tc, "Hi there!")

      assert tc.actual_output == "Hi there!"
    end
  end

  describe "with_metadata/2" do
    test "adds metadata" do
      tc = TestCase.new(input: "Hello")
      tc = TestCase.with_metadata(tc, %{latency_ms: 150})

      assert tc.metadata == %{latency_ms: 150}
    end

    test "merges metadata" do
      tc =
        TestCase.new(input: "Hello")
        |> TestCase.with_metadata(%{latency_ms: 150})
        |> TestCase.with_metadata(%{tokens: 50})

      assert tc.metadata == %{latency_ms: 150, tokens: 50}
    end
  end
end
