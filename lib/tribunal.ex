defmodule Tribunal do
  @moduledoc """
  LLM evaluation framework for Elixir.

  Tribunal provides tools for evaluating LLM outputs and measuring response
  quality.

  ## Quick Start

  ### In Tests (ExUnit)

      defmodule MyApp.RAGEvalTest do
        use ExUnit.Case
        use Tribunal.ExUnit

        @moduletag :eval

        test "response is grounded in context" do
          response = MyApp.RAG.query("What's the return policy?")

          assert response =~ "30 days"
          assert_faithful response, context: @docs, threshold: 0.8
        end
      end

  ### Dataset-Driven Evals

      # test/evals/datasets/questions.json
      [
        {
          "input": "What's the return policy?",
          "context": "Returns within 30 days with receipt.",
          "expected": {
            "contains": "30 days",
            "faithful": {"threshold": 0.8}
          }
        }
      ]

  Then run: `mix tribunal.eval`

  ## Assertion Types

  ### Deterministic (no LLM, instant)

  - `contains` - Output includes one substring
  - `not_contains` - Output excludes substring(s)
  - `contains_any` - Output includes at least one
  - `contains_all` - Output includes all
  - `regex` - Output matches pattern
  - `is_json` - Output is valid JSON
  - `latency_ms` - Response within time limit

  ### LLM-as-Judge (requires `req_llm`)

  - `faithful` - Response grounded in context
  - `relevant` - Response addresses query
  - `correctness` - Response matches expected answer
  - `refusal` - Output is a refusal
  - `no_bias` - Response contains no bias or stereotypes
  - `no_toxicity` - Response contains no toxic language
  - `no_harmful_content` - Response contains no dangerous content
  - `no_pii` - Response contains no personal information
  - `no_policy_violation` - Response follows a supplied policy
  - `no_excessive_agency` - Response does not claim actions it cannot perform
  - `no_hijacking` - Response stays within its purpose
  - `no_imitation` - Response does not impersonate a brand, person, or authority
  - `no_prompt_extraction` - Response does not leak system prompts or internal instructions

  ### Embedding (requires `alike`)

  - `similar` - Semantic similarity to golden answer

  ## Installation

      def deps do
        [
          {:tribunal, "~> 2.0"},

          # Optional: LLM-as-judge metrics
          {:req_llm, ">= 1.2.0 and < 2.0.0"},

          # Optional: embedding similarity
          {:alike, ">= 0.4.0 and < 0.5.0"}
        ]
      end
  """

  alias Tribunal.{Assertions, Evaluator, TestCase}

  @doc """
  Evaluates a test case against assertions.

  ## Examples

      test_case = %Tribunal.TestCase{
        input: "What's the return policy?",
        actual_output: "Returns within 30 days.",
        context: ["Return policy: 30 days with receipt."]
      }

      assertions = [
        {:contains, [value: "30 days"]},
        {:faithful, [threshold: 0.8]}
      ]

      Tribunal.evaluate(test_case, assertions)
      #=> %{status: :passed, evaluations: [...], failures: []}
  """
  def evaluate(%TestCase{} = test_case, assertions) when is_list(assertions) do
    Evaluator.evaluate(test_case, assertions)
  end

  def evaluate(%TestCase{} = test_case, assertions) when is_map(assertions) do
    Evaluator.evaluate(test_case, assertions)
  end

  @doc """
  Returns available assertion types based on loaded dependencies.
  """
  def available_assertions do
    Assertions.available()
  end

  @doc """
  Creates a new test case.

  ## Examples

      Tribunal.test_case(
        input: "What's the price?",
        actual_output: "The price is $29.99.",
        context: ["Product costs $29.99"]
      )
  """
  def test_case(attrs) do
    TestCase.new(attrs)
  end
end
