defmodule Tribunal.Assertions do
  @moduledoc """
  Assertion evaluation engine.

  Routes assertions to the appropriate implementation:
  - Deterministic: `contains`, `regex`, `is_json`, etc.
  - Judge (requires req_llm): `faithful`, `relevant`, etc.
  - Embedding (requires alike): `similar`
  """

  alias Tribunal.Assertions.{Deterministic, Embedding, Judge}
  alias Tribunal.TestCase

  @deterministic_assertions [
    :contains,
    :not_contains,
    :contains_any,
    :contains_all,
    :regex,
    :is_json,
    :max_tokens,
    :latency_ms,
    :starts_with,
    :ends_with,
    :equals,
    :min_length,
    :max_length,
    :word_count,
    :is_url,
    :is_email,
    :levenshtein
  ]

  # Judge assertions are dynamically determined from Tribunal.Judge

  @embedding_assertions [:similar]

  @doc """
  Evaluates a single assertion against a test case.

  Returns `{:pass, details}` or `{:fail, details}`.
  """
  def evaluate(assertion_type, test_case, opts \\ [])

  def evaluate(assertion_type, %TestCase{} = test_case, opts) when is_atom(assertion_type) do
    cond do
      assertion_type in @deterministic_assertions ->
        Deterministic.evaluate(assertion_type, test_case.actual_output, opts)

      Tribunal.Judge.builtin_judge?(assertion_type) or
          Tribunal.Judge.custom_judge?(assertion_type) ->
        evaluate_judge(assertion_type, test_case, opts)

      assertion_type in @embedding_assertions ->
        evaluate_embedding(assertion_type, test_case, opts)

      true ->
        {:error, "Unknown assertion type: #{assertion_type}"}
    end
  end

  def evaluate(assertion_type, %TestCase{}, _opts) do
    {:error, "Unknown assertion type: #{assertion_type}"}
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
  Evaluates assertions in order without collapsing repeated assertion types.

  Default options are applied to every assertion. Options declared on the
  assertion take precedence over defaults.
  """
  def evaluate_each(assertions, test_case, defaults \\ [])

  def evaluate_each(assertions, %TestCase{} = test_case, defaults) when is_map(assertions) do
    assertions
    |> Enum.to_list()
    |> evaluate_each(test_case, defaults)
  end

  def evaluate_each(assertions, %TestCase{} = test_case, defaults) when is_list(assertions) do
    defaults = normalize_opts(defaults)

    Enum.map(assertions, fn
      {type, opts} ->
        case merge_opts(defaults, opts) do
          {:ok, merged_opts} -> {type, safely_evaluate(type, test_case, merged_opts)}
          {:error, reason} -> {type, {:error, reason}}
        end

      type when is_atom(type) or is_binary(type) ->
        {type, safely_evaluate(type, test_case, defaults)}
    end)
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
        Tribunal.Judge.all_judge_names()
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

    Judge.evaluate(type, test_case, opts)
  end

  defp evaluate_embedding(_type, test_case, opts) do
    unless Code.ensure_loaded?(Alike) do
      raise """
      Embedding similarity requires Alike.

      Add to mix.exs:
        {:alike, "~> 0.4"}
      """
    end

    Embedding.evaluate(test_case, opts)
  end

  defp safely_evaluate(type, test_case, opts) do
    evaluate(type, test_case, opts)
  rescue
    error -> {:error, Exception.message(error)}
  catch
    kind, reason -> {:error, "#{kind}: #{inspect(reason)}"}
  end

  defp normalize_opts(opts) when is_map(opts), do: Map.to_list(opts)
  defp normalize_opts(opts) when is_list(opts), do: opts

  defp merge_opts(defaults, opts) do
    opts = normalize_opts(opts)

    if Keyword.keyword?(defaults) and Keyword.keyword?(opts) do
      {:ok, Keyword.merge(defaults, opts)}
    else
      {:error, "Assertion options must use known atom keys"}
    end
  end
end
