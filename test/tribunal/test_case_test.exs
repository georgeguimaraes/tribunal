defmodule Tribunal.TestCaseTest do
  use ExUnit.Case, async: true

  alias Tribunal.TestCase

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

    test "ignores unknown external keys without creating atoms" do
      key = "unknown_#{System.unique_integer([:positive])}"
      refute existing_atom?(key)

      tc = TestCase.new(%{"input" => "Hello", key => "ignored"})

      assert tc.input == "Hello"
      refute existing_atom?(key)
    end

    test "preserves structured input and its explicit evaluation text" do
      tc =
        TestCase.new(%{
          "input" => %{"query" => "return policy", "account_id" => 42},
          "evaluation_input" => "return policy for account 42"
        })

      assert tc.input == %{"query" => "return policy", "account_id" => 42}
      assert TestCase.evaluation_input(tc) == "return policy for account 42"
    end
  end

  describe "input representations" do
    test "uses JSON as the default judge and display representation for structured input" do
      tc = TestCase.new(input: %{"query" => "hello", "flags" => [true, 2]})

      assert TestCase.validate(tc) == :ok
      assert TestCase.evaluation_input(tc) == ~s({"flags":[true,2],"query":"hello"})
      assert TestCase.display_input(tc) == ~s({"flags":[true,2],"query":"hello"})
    end

    test "rejects unsupported values and atom map keys" do
      assert {:error, "input must be JSON-compatible"} =
               TestCase.validate(%TestCase{input: {:query, "hello"}})

      assert {:error, "input maps must use string keys and JSON-compatible values"} =
               TestCase.validate(%TestCase{input: %{query: "hello"}})
    end

    test "accepts valid UTF-8 strings in nested values and map keys" do
      input = %{"pergunta" => ["olá", %{"resposta" => "amanhã"}]}

      assert TestCase.validate_input(input) == :ok
    end

    test "rejects invalid UTF-8 string values at any depth" do
      invalid_utf8 = <<255>>

      assert {:error, "input must be JSON-compatible"} =
               TestCase.validate_input(invalid_utf8)

      assert {:error, "input maps must use string keys and JSON-compatible values"} =
               TestCase.validate_input(%{"nested" => ["valid", invalid_utf8]})
    end

    test "rejects invalid UTF-8 map keys" do
      assert {:error, "input maps must use string keys and JSON-compatible values"} =
               TestCase.validate_input(%{<<255>> => "value"})
    end

    test "rejects improper lists without raising" do
      improper = ["first" | "invalid tail"]

      assert {:error, "input must be JSON-compatible"} =
               TestCase.validate_input(improper)

      assert {:error, "input maps must use string keys and JSON-compatible values"} =
               TestCase.validate_input(%{"nested" => improper})
    end

    test "always produces display text for invalid direct structs" do
      assert TestCase.display_input(%TestCase{input: {:query, "hello"}}) ==
               ~s({:query, "hello"})
    end

    test "prefers a metadata name for generated test labels" do
      tc = %TestCase{input: %{"query" => "hello"}, metadata: %{"name" => "friendly case"}}

      assert TestCase.display_name(tc) == "friendly case"
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

  defp existing_atom?(value) do
    _atom = String.to_existing_atom(value)
    true
  rescue
    ArgumentError -> false
  end
end
