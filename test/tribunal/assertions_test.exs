defmodule Tribunal.AssertionsTest do
  use ExUnit.Case, async: true

  alias Tribunal.{Assertions, TestCase}

  describe "evaluate/3" do
    test "evaluates deterministic assertion" do
      test_case = %TestCase{
        input: "test",
        actual_output: "Hello world"
      }

      assert {:pass, _} = Assertions.evaluate(:contains, test_case, value: "world")
    end

    test "returns failure for failing assertion" do
      test_case = %TestCase{
        input: "test",
        actual_output: "Hello world"
      }

      assert {:fail, _} = Assertions.evaluate(:contains, test_case, value: "foo")
    end

    test "returns error for unknown assertion" do
      test_case = %TestCase{input: "test", actual_output: "output"}

      assert {:error, msg} = Assertions.evaluate(:unknown_assertion, test_case, [])
      assert msg =~ "Unknown assertion"
    end
  end

  describe "evaluate_all/2" do
    test "evaluates multiple assertions" do
      test_case = %TestCase{
        input: "test",
        actual_output: "Hello world, price is $29.99"
      }

      assertions = [
        {:contains, [value: "Hello"]},
        {:regex, [value: ~r/\$\d+\.\d{2}/]}
      ]

      results = Assertions.evaluate_all(assertions, test_case)

      assert {:pass, _} = results[:contains]
      assert {:pass, _} = results[:regex]
    end

    test "accepts map of assertions" do
      test_case = %TestCase{
        input: "test",
        actual_output: "Hello world"
      }

      assertions = %{
        contains: [value: "Hello"],
        not_contains: [value: "foo"]
      }

      results = Assertions.evaluate_all(assertions, test_case)

      assert {:pass, _} = results[:contains]
      assert {:pass, _} = results[:not_contains]
    end

    test "handles atom-only assertions" do
      test_case = %TestCase{
        input: "test",
        actual_output: ~s({"valid": "json"})
      }

      assertions = [:is_json]
      results = Assertions.evaluate_all(assertions, test_case)

      assert {:pass, _} = results[:is_json]
    end
  end

  describe "all_passed?/1" do
    test "returns true when all pass" do
      results = %{
        contains: {:pass, %{}},
        regex: {:pass, %{}}
      }

      assert Assertions.all_passed?(results)
    end

    test "returns false when any fails" do
      results = %{
        contains: {:pass, %{}},
        regex: {:fail, %{reason: "No match"}}
      }

      refute Assertions.all_passed?(results)
    end
  end

  describe "evaluate/3 with judge assertions" do
    defp mock_client(response) do
      fn _model, _messages, _opts -> response end
    end

    test "evaluates faithful assertion via Judge module" do
      test_case = %TestCase{
        input: "What is the policy?",
        actual_output: "30 day returns.",
        context: ["Returns within 30 days."]
      }

      client = mock_client({:ok, %{"verdict" => "yes", "reason" => "Matches", "score" => 1.0}})

      assert {:pass, _} = Assertions.evaluate(:faithful, test_case, llm: client)
    end

    test "evaluates relevant assertion via Judge module" do
      test_case = %TestCase{
        input: "What are the hours?",
        actual_output: "9am to 5pm."
      }

      client = mock_client({:ok, %{"verdict" => "yes", "reason" => "Relevant", "score" => 1.0}})

      assert {:pass, _} = Assertions.evaluate(:relevant, test_case, llm: client)
    end
  end

  describe "available/0" do
    test "includes deterministic assertions" do
      available = Assertions.available()

      assert :contains in available
      assert :not_contains in available
      assert :regex in available
      assert :is_json in available
      assert :max_tokens in available
      assert :latency_ms in available
      # New assertions
      assert :starts_with in available
      assert :ends_with in available
      assert :equals in available
      assert :min_length in available
      assert :max_length in available
      assert :word_count in available
      assert :is_url in available
      assert :is_email in available
      assert :levenshtein in available
    end

    test "includes judge assertions when req_llm loaded" do
      available = Assertions.available()

      # req_llm is in deps
      assert :faithful in available
      assert :relevant in available
      assert :hallucination in available
      assert :correctness in available
      assert :bias in available
      assert :toxicity in available
      assert :harmful in available
    end

    test "includes embedding assertions when alike loaded" do
      available = Assertions.available()

      # alike is in deps
      assert :similar in available
    end
  end
end
