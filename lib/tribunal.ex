defmodule Tribunal do
  @moduledoc """
  LLM evaluation framework for Elixir.

  Tribunal provides tools for evaluating LLM outputs,
  detecting hallucinations, and measuring response quality.

  ## Quick Start

  ### In Tests (ExUnit)

      defmodule MyApp.RAGEvalTest do
        use ExUnit.Case
        use Tribunal.EvalCase

        @moduletag :eval

        test "response is grounded in context" do
          response = MyApp.RAG.query("What's the return policy?")

          assert_contains response, "30 days"
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
            "contains": ["30 days"],
            "faithful": {"threshold": 0.8}
          }
        }
      ]

  Then run: `mix tribunal.eval`

  ## Assertion Types

  ### Deterministic (no LLM, instant)

  - `contains` - Output includes substring(s)
  - `not_contains` - Output excludes substring(s)
  - `contains_any` - Output includes at least one
  - `contains_all` - Output includes all
  - `regex` - Output matches pattern
  - `is_json` - Output is valid JSON
  - `is_refusal` - Output is a refusal
  - `max_tokens` - Output under token limit
  - `latency_ms` - Response within time limit

  ### LLM-as-Judge (requires `req_llm`)

  - `faithful` - Response grounded in context
  - `relevant` - Response addresses query
  - `hallucination` - Response contains fabricated info
  - `coherent` - Response is logically consistent
  - `toxicity` - Response contains harmful content
  - `rubric` - Custom evaluation criteria

  ### Embedding (requires `alike`)

  - `similar` - Semantic similarity to golden answer

  ## Installation

      def deps do
        [
          {:tribunal, "~> 0.1"},

          # Optional: LLM-as-judge metrics
          {:req_llm, "~> 1.2"},

          # Optional: embedding similarity
          {:alike, "~> 0.4"}
        ]
      end
  """

  alias Tribunal.{Assertions, TestCase}

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
      #=> %{contains: {:pass, ...}, faithful: {:pass, ...}}
  """
  def evaluate(%TestCase{} = test_case, assertions) when is_list(assertions) do
    Assertions.evaluate_all(assertions, test_case)
  end

  def evaluate(%TestCase{} = test_case, assertions) when is_map(assertions) do
    Assertions.evaluate_all(assertions, test_case)
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
