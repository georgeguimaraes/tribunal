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

  @deterministic_options %{
    contains: [:value, :values],
    not_contains: [:value, :values],
    contains_any: [:value, :values],
    contains_all: [:value, :values],
    regex: [:value, :pattern],
    is_json: [],
    max_tokens: [:value, :max],
    latency_ms: [:value, :max, :actual, :latency],
    starts_with: [:value],
    ends_with: [:value],
    equals: [:value],
    min_length: [:value, :min],
    max_length: [:value, :max],
    word_count: [:min, :max],
    is_url: [],
    is_email: [],
    levenshtein: [:value, :max_distance]
  }

  @judge_options [
    :threshold,
    :model,
    :llm,
    :llm_client,
    :temperature,
    :max_tokens,
    :verbose,
    :purpose,
    :policy,
    :context,
    :query,
    :expected,
    :input
  ]

  @doc false
  def resolve_type(type) when is_atom(type), do: type

  def resolve_type(type) when is_binary(type) do
    Enum.find(registered_types(), type, &(Atom.to_string(&1) == type))
  end

  @doc """
  Evaluates a single assertion against a test case.

  Returns `{:pass, details}` or `{:fail, details}`.
  """
  def evaluate(assertion_type, test_case, opts \\ [])

  def evaluate(assertion_type, %TestCase{} = test_case, opts) when is_atom(assertion_type) do
    with :ok <- validate_options(assertion_type, opts) do
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
  end

  def evaluate(assertion_type, %TestCase{}, _opts) do
    {:error, "Unknown assertion type: #{assertion_type}"}
  end

  @doc """
  Evaluates multiple assertions against a test case.

  Returns a map of `%{assertion_type => result}`.
  """
  def evaluate_all(assertions, %TestCase{} = test_case) when is_list(assertions) do
    assertions
    |> evaluate_each(test_case)
    |> summarize()
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
        case merge_opts(defaults_for(type, defaults), opts) do
          {:ok, merged_opts} -> {type, safely_evaluate(type, test_case, merged_opts)}
          {:error, reason} -> {type, {:error, reason}}
        end

      type when is_atom(type) or is_binary(type) ->
        {type, safely_evaluate(type, test_case, defaults_for(type, defaults))}
    end)
  end

  @doc false
  def summarize(evaluations) do
    Enum.reduce(evaluations, %{}, fn {type, result}, summary ->
      Map.update(summary, type, result, &worst_result(&1, result))
    end)
  end

  @doc """
  Checks if all assertions passed.
  """
  def all_passed?(results) when is_map(results) do
    map_size(results) > 0 and
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

  defp registered_types do
    @deterministic_assertions ++ @embedding_assertions ++ Tribunal.Judge.all_judge_names()
  end

  defp validate_options(type, opts) when is_list(opts) do
    cond do
      not Keyword.keyword?(opts) ->
        {:error, "Assertion options must use known atom keys"}

      Tribunal.Judge.custom_judge?(type) ->
        :ok

      allowed = allowed_options(type) ->
        case Keyword.keys(opts) -- allowed do
          [] -> :ok
          unknown -> {:error, "Unknown options for #{type}: #{inspect(unknown)}"}
        end

      true ->
        :ok
    end
  end

  defp validate_options(_type, _opts), do: {:error, "Assertion options must be a keyword list"}

  defp allowed_options(type) when type in @embedding_assertions,
    do: [:threshold, :alike_fn, :expected, :verbose]

  defp allowed_options(type), do: Map.get(@deterministic_options, type) || judge_options(type)

  defp judge_options(type) do
    if type in Tribunal.Judge.builtin_judge_names(), do: @judge_options
  end

  defp defaults_for(type, defaults) do
    case allowed_options(type) do
      nil -> defaults
      allowed -> Keyword.take(defaults, allowed)
    end
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

  defp merge_opts(defaults, opts) when is_map(opts) or is_list(opts) do
    opts = normalize_opts(opts)

    if Keyword.keyword?(defaults) and Keyword.keyword?(opts) do
      {:ok, Keyword.merge(defaults, opts)}
    else
      {:error, "Assertion options must use known atom keys"}
    end
  end

  defp merge_opts(_defaults, _opts), do: {:error, "Assertion options must be a keyword list"}

  defp worst_result({:error, _} = error, _result), do: error
  defp worst_result(_existing, {:error, _} = error), do: error
  defp worst_result({:fail, _} = failure, _result), do: failure
  defp worst_result(_existing, {:fail, _} = failure), do: failure
  defp worst_result(_existing, result), do: result
end
