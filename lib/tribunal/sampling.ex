defmodule Tribunal.Sampling do
  @moduledoc """
  Reduces ordered evaluation attempts into one case result.

  Sampling measures application nondeterminism. An operational error in any
  attempt always fails the reduced result, regardless of the quality-oriented
  pass rule.
  """

  @type pass_rule :: :all | :any | :majority | {:rate, float()}
  @type assertion_stat :: %{
          index: non_neg_integer(),
          type: atom() | String.t(),
          passed: non_neg_integer(),
          failed: non_neg_integer(),
          errors: non_neg_integer(),
          pass_rate: float()
        }
  @type sample :: %{
          repeat: pos_integer(),
          pass_rule: pass_rule(),
          passed: non_neg_integer(),
          failed: non_neg_integer(),
          errors: non_neg_integer(),
          pass_rate: float(),
          assertions: [assertion_stat()]
        }

  @doc """
  Reduces a nonempty ordered list of evaluator result maps.

  Supported pass rules are `:all`, `:any`, `:majority`, and
  `{:rate, value}` where `value` is a float between `0.0` and `1.0`.

  For one attempt, all existing top-level values are preserved. For repeated
  attempts, compatibility fields for the output and assertion results project
  the final attempt while status, failures, execution error, and duration are
  reduced across every attempt.
  """
  @spec reduce([map()], pass_rule()) :: map()
  def reduce(attempts, pass_rule) do
    validate_attempts!(attempts)
    validate_pass_rule!(pass_rule)
    validate_assertion_alignment!(attempts)

    sample = sample(attempts, pass_rule)

    case attempts do
      [attempt] ->
        attempt
        |> Map.put(:attempts, attempts)
        |> Map.put(:sample, sample)

      _multiple ->
        final_attempt = List.last(attempts)
        execution_error = sample.errors > 0
        passed = not execution_error and passes_rule?(sample, pass_rule)

        final_attempt
        |> Map.put(:status, if(passed, do: :passed, else: :failed))
        |> Map.put(:failures, reduced_failures(attempts, passed))
        |> Map.put(:execution_error, execution_error)
        |> Map.put(:duration_ms, Enum.sum(Enum.map(attempts, & &1.duration_ms)))
        |> Map.put(:attempts, attempts)
        |> Map.put(:sample, sample)
    end
  end

  defp sample(attempts, pass_rule) do
    repeat = length(attempts)
    passed = Enum.count(attempts, &(&1.status == :passed))
    errors = Enum.count(attempts, & &1.execution_error)

    %{
      repeat: repeat,
      pass_rule: pass_rule,
      passed: passed,
      failed: repeat - passed,
      errors: errors,
      pass_rate: passed / repeat,
      assertions: assertion_stats(attempts)
    }
  end

  defp assertion_stats([first | _] = attempts) do
    first.evaluations
    |> Enum.with_index()
    |> Enum.map(fn {{type, _result}, index} ->
      results = Enum.map(attempts, &(&1.evaluations |> Enum.at(index) |> elem(1)))
      repeat = length(results)
      passed = Enum.count(results, &match?({:pass, _details}, &1))
      errors = Enum.count(results, &(assertion_status(&1) == :error))

      %{
        index: index,
        type: type,
        passed: passed,
        failed: repeat - passed,
        errors: errors,
        pass_rate: passed / repeat
      }
    end)
  end

  defp assertion_status({:pass, _details}), do: :passed
  defp assertion_status({:fail, _details}), do: :failed
  defp assertion_status(_result), do: :error

  defp passes_rule?(%{passed: passed, repeat: repeat}, :all), do: passed == repeat
  defp passes_rule?(%{passed: passed}, :any), do: passed >= 1
  defp passes_rule?(%{passed: passed, repeat: repeat}, :majority), do: passed * 2 > repeat

  defp passes_rule?(%{pass_rate: pass_rate}, {:rate, required_rate}),
    do: pass_rate >= required_rate

  defp reduced_failures(_attempts, true), do: []

  defp reduced_failures(attempts, false) do
    attempts
    |> Enum.with_index(1)
    |> Enum.flat_map(fn
      {%{status: :passed}, _index} ->
        []

      {%{failures: []}, index} ->
        [{:sampling, "Attempt #{index} failed without failure details"}]

      {%{failures: failures}, index} ->
        Enum.map(failures, fn {type, reason} ->
          {type, "Attempt #{index}: #{reason}"}
        end)
    end)
  end

  defp validate_attempts!([]) do
    raise ArgumentError, "attempts must be a nonempty ordered list of evaluator result maps"
  end

  defp validate_attempts!(attempts) when is_list(attempts) do
    Enum.each(Enum.with_index(attempts, 1), fn {attempt, index} ->
      validate_attempt!(attempt, index)
    end)
  end

  defp validate_attempts!(_attempts) do
    raise ArgumentError, "attempts must be a nonempty ordered list of evaluator result maps"
  end

  defp validate_attempt!(attempt, index) when is_map(attempt) do
    validate_status!(attempt, index)
    validate_execution_error!(attempt, index)
    validate_duration!(attempt, index)
    validate_failures!(attempt, index)
    validate_evaluations!(attempt, index)

    if attempt.execution_error and attempt.status != :failed do
      raise ArgumentError,
            "attempt #{index} has execution_error: true but status is not :failed"
    end
  end

  defp validate_attempt!(_attempt, index) do
    raise ArgumentError, "attempt #{index} must be an evaluator result map"
  end

  defp validate_status!(attempt, index) do
    case Map.fetch(attempt, :status) do
      {:ok, status} when status in [:passed, :failed] ->
        :ok

      {:ok, status} ->
        raise ArgumentError, "attempt #{index} has invalid status: #{inspect(status)}"

      :error ->
        raise ArgumentError, "attempt #{index} is missing required :status"
    end
  end

  defp validate_execution_error!(attempt, index) do
    case Map.fetch(attempt, :execution_error) do
      {:ok, value} when is_boolean(value) ->
        :ok

      {:ok, value} ->
        raise ArgumentError,
              "attempt #{index} has invalid :execution_error value: #{inspect(value)}"

      :error ->
        raise ArgumentError, "attempt #{index} is missing required :execution_error"
    end
  end

  defp validate_duration!(attempt, index) do
    case Map.fetch(attempt, :duration_ms) do
      {:ok, value} when is_integer(value) and value >= 0 ->
        :ok

      {:ok, value} ->
        raise ArgumentError,
              "attempt #{index} has invalid :duration_ms value: #{inspect(value)}"

      :error ->
        raise ArgumentError, "attempt #{index} is missing required :duration_ms"
    end
  end

  defp validate_failures!(attempt, index) do
    case Map.fetch(attempt, :failures) do
      {:ok, failures} when is_list(failures) ->
        unless Enum.all?(failures, &valid_failure?/1) do
          raise ArgumentError,
                "attempt #{index} has invalid :failures; expected {type, reason} tuples"
        end

      {:ok, value} ->
        raise ArgumentError, "attempt #{index} has invalid :failures value: #{inspect(value)}"

      :error ->
        raise ArgumentError, "attempt #{index} is missing required :failures"
    end
  end

  defp valid_failure?({type, reason})
       when (is_atom(type) or is_binary(type)) and is_binary(reason),
       do: true

  defp valid_failure?(_failure), do: false

  defp validate_evaluations!(attempt, index) do
    case Map.fetch(attempt, :evaluations) do
      {:ok, evaluations} when is_list(evaluations) ->
        unless Enum.all?(evaluations, &valid_evaluation?/1) do
          raise ArgumentError,
                "attempt #{index} has invalid :evaluations; expected {assertion_type, result} tuples"
        end

      {:ok, value} ->
        raise ArgumentError, "attempt #{index} has invalid :evaluations value: #{inspect(value)}"

      :error ->
        raise ArgumentError, "attempt #{index} is missing required :evaluations"
    end
  end

  defp valid_evaluation?({type, _result}) when is_atom(type) or is_binary(type), do: true
  defp valid_evaluation?(_evaluation), do: false

  defp validate_assertion_alignment!([first | rest]) do
    expected_types = Enum.map(first.evaluations, &elem(&1, 0))

    Enum.each(Enum.with_index(rest, 2), fn {attempt, index} ->
      actual_types = Enum.map(attempt.evaluations, &elem(&1, 0))

      unless actual_types == expected_types do
        raise ArgumentError,
              "attempt #{index} assertion declarations do not align by index: " <>
                "expected #{inspect(expected_types)}, got #{inspect(actual_types)}"
      end
    end)
  end

  @doc false
  @spec validate_pass_rule!(term()) :: :ok
  def validate_pass_rule!(rule) when rule in [:all, :any, :majority], do: :ok

  def validate_pass_rule!({:rate, rate}) when is_float(rate) and rate >= 0.0 and rate <= 1.0,
    do: :ok

  def validate_pass_rule!({:rate, rate}) do
    raise ArgumentError,
          "rate pass rule must be {:rate, float} with a value between 0.0 and 1.0, " <>
            "got: #{inspect({:rate, rate})}"
  end

  def validate_pass_rule!(rule) do
    raise ArgumentError,
          "unsupported pass rule #{inspect(rule)}; expected :all, :any, :majority, " <>
            "or {:rate, float}"
  end
end
