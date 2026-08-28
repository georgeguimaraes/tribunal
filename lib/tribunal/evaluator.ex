defmodule Tribunal.Evaluator do
  @moduledoc """
  Evaluates one test case and classifies its outcome.

  This module contains the evaluation semantics shared by the Mix task and
  `Tribunal.EvalCase`. It does not invoke providers, aggregate a suite, format
  reports, or interact with ExUnit.
  """

  alias Tribunal.{Assertions, TestCase}

  @type assertion_result :: {atom() | String.t(), {:pass | :fail, map()} | {:error, term()}}

  @type result :: %{
          input: term(),
          actual_output: term(),
          status: :passed | :failed,
          failures: [{atom() | String.t(), String.t()}],
          results: map(),
          evaluations: [assertion_result()],
          duration_ms: non_neg_integer()
        }

  @doc """
  Evaluates all configured assertions for one populated test case.

  Default options are merged into each assertion, with assertion-specific
  options taking precedence. Missing output, missing assertions, assertion
  errors, and unexpected assertion results fail closed.
  """
  @spec evaluate(TestCase.t(), list() | map(), keyword()) :: result()
  def evaluate(%TestCase{} = test_case, assertions, opts \\ []) do
    started_at = Keyword.get_lazy(opts, :started_at, &now/0)
    defaults = Keyword.get(opts, :defaults, [])

    evaluations = evaluate_assertions(test_case, assertions, defaults)
    failures = failures(test_case, assertions, evaluations)

    %{
      input: test_case.input,
      actual_output: test_case.actual_output,
      status: if(failures == [], do: :passed, else: :failed),
      failures: failures,
      results: Map.new(evaluations),
      evaluations: evaluations,
      duration_ms: now() - started_at
    }
  end

  @doc """
  Builds a failed case result when execution fails before assertions can run.
  """
  @spec error(TestCase.t(), term(), keyword()) :: result()
  def error(%TestCase{} = test_case, reason, opts \\ []) do
    started_at = Keyword.get_lazy(opts, :started_at, &now/0)

    %{
      input: test_case.input,
      actual_output: test_case.actual_output,
      status: :failed,
      failures: [{:provider, reason(reason, "Provider failed")}],
      results: %{},
      evaluations: [],
      duration_ms: now() - started_at
    }
  end

  @doc false
  def failure_message(%{failures: failures}) do
    Enum.map_join(failures, "\n", fn {type, reason} -> "#{type}: #{reason}" end)
  end

  defp evaluate_assertions(%TestCase{actual_output: nil}, _assertions, _defaults), do: []

  defp evaluate_assertions(test_case, assertions, defaults) do
    Assertions.evaluate_each(assertions, test_case, defaults)
  end

  defp failures(%TestCase{actual_output: nil}, _assertions, _evaluations) do
    [{:evaluation, "Missing actual output"}]
  end

  defp failures(_test_case, assertions, _evaluations)
       when assertions == [] or assertions == %{} do
    [{:evaluation, "No assertions configured"}]
  end

  defp failures(_test_case, _assertions, evaluations) do
    Enum.flat_map(evaluations, fn
      {_type, {:pass, _details}} ->
        []

      {type, {:fail, details}} ->
        [{type, reason(details, "Assertion failed")}]

      {type, {:error, error}} ->
        [{type, reason(error, "Assertion errored")}]

      {type, result} ->
        [{type, "Unexpected assertion result: #{inspect(result)}"}]
    end)
  end

  defp reason(%{reason: reason}, _fallback) when is_binary(reason), do: reason
  defp reason(details, fallback) when is_map(details), do: Map.get(details, "reason", fallback)
  defp reason(reason, _fallback) when is_binary(reason), do: reason
  defp reason(reason, fallback) when is_nil(reason), do: fallback
  defp reason(reason, _fallback), do: inspect(reason)

  defp now, do: System.monotonic_time(:millisecond)
end
