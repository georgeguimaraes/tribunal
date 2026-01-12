defmodule Judicium.Assertions do
  @moduledoc """
  Assertion evaluation engine.

  Routes assertions to the appropriate implementation:
  - Deterministic: `contains`, `regex`, `is_json`, etc.
  - Judge (requires req_llm): `faithful`, `relevant`, etc.
  - Embedding (requires alike): `similar`
  """

  alias Judicium.Assertions.Deterministic
  alias Judicium.TestCase

  @deterministic_assertions [
    :contains,
    :not_contains,
    :contains_any,
    :contains_all,
    :regex,
    :is_json,
    :is_refusal,
    :max_tokens,
    :latency_ms,
    :starts_with,
    :ends_with,
    :equals,
    :min_length,
    :max_length,
    :word_count,
    :no_pii,
    :no_toxic,
    :is_url,
    :is_email,
    :levenshtein
  ]

  @judge_assertions [
    :faithful,
    :relevant,
    :hallucination,
    :correctness,
    :bias,
    :toxicity,
    :harmful
  ]

  @embedding_assertions [:similar]

  @doc """
  Evaluates a single assertion against a test case.

  Returns `{:pass, details}` or `{:fail, details}`.
  """
  def evaluate(assertion_type, %TestCase{} = test_case, opts \\ []) do
    cond do
      assertion_type in @deterministic_assertions ->
        Deterministic.evaluate(assertion_type, test_case.actual_output, opts)

      assertion_type in @judge_assertions ->
        evaluate_judge(assertion_type, test_case, opts)

      assertion_type in @embedding_assertions ->
        evaluate_embedding(assertion_type, test_case, opts)

      true ->
        {:error, "Unknown assertion type: #{assertion_type}"}
    end
  end

  @doc """
  Evaluates multiple assertions against a test case.

  Returns a map of `%{assertion_type => result}`.
  """
  def evaluate_all(assertions, %TestCase{} = test_case) when is_list(assertions) do
    Map.new(assertions, fn
      {type, opts} -> {type, evaluate(type, test_case, opts)}
      type when is_atom(type) -> {type, evaluate(type, test_case, [])}
    end)
  end

  def evaluate_all(assertions, %TestCase{} = test_case) when is_map(assertions) do
    assertions
    |> Enum.to_list()
    |> evaluate_all(test_case)
  end

  @doc """
  Checks if all assertions passed.
  """
  def all_passed?(results) when is_map(results) do
    Enum.all?(results, fn {_type, result} -> match?({:pass, _}, result) end)
  end

  @doc """
  Returns list of available assertion types based on loaded dependencies.
  """
  def available do
    base = @deterministic_assertions

    judge =
      if Code.ensure_loaded?(ReqLLM) do
        @judge_assertions
      else
        []
      end

    embedding =
      if Code.ensure_loaded?(Alike) do
        @embedding_assertions
      else
        []
      end

    base ++ judge ++ embedding
  end

  defp evaluate_judge(type, test_case, opts) do
    unless Code.ensure_loaded?(ReqLLM) do
      raise """
      LLM-as-judge assertions require ReqLLM.

      Add to mix.exs:
        {:req_llm, "~> 1.2"}
      """
    end

    Judicium.Assertions.Judge.evaluate(type, test_case, opts)
  end

  defp evaluate_embedding(_type, test_case, opts) do
    unless Code.ensure_loaded?(Alike) do
      raise """
      Embedding similarity requires Alike.

      Add to mix.exs:
        {:alike, "~> 0.4"}
      """
    end

    Judicium.Assertions.Embedding.evaluate(test_case, opts)
  end
end
