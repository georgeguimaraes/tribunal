defmodule Tribunal.Batch.Report do
  @moduledoc false

  @spec build([map()], integer()) :: map()
  def build(cases, started_at) do
    duration_ms = System.monotonic_time(:millisecond) - started_at

    %{
      schema_version: 3,
      summary: summarize(cases, duration_ms),
      metrics: aggregate_metrics(cases),
      cases: cases
    }
  end

  @spec apply_gates(map(), map()) :: {map(), boolean()}
  def apply_gates(report, gates) do
    overall = overall_gate(report.summary, Map.get(gates, :overall))
    groups = group_gates(report.cases, Map.get(gates, :groups))
    configured = not is_nil(overall) or not is_nil(groups)
    operational_error = report.summary.errors > 0

    gate_status =
      cond do
        operational_error -> :error
        report.summary.total == 0 -> :failed
        not configured -> :not_configured
        gate_passed?(overall) and groups_passed?(groups) -> :passed
        true -> :failed
      end

    threshold_passed =
      if configured, do: gate_status == :passed, else: nil

    report =
      report
      |> put_in([:summary, :gate_status], gate_status)
      |> put_in([:summary, :threshold_passed], threshold_passed)
      |> Map.put(:gates, %{overall: overall, groups: groups})

    {report, gate_status in [:passed, :not_configured]}
  end

  @spec validate_group_cases!([{Tribunal.TestCase.t(), term()}], String.t() | atom() | nil) :: :ok
  def validate_group_cases!(_cases, nil), do: :ok

  def validate_group_cases!(cases, field) when is_binary(field) or is_atom(field) do
    Enum.each(Enum.with_index(cases, 1), fn {{test_case, _assertions}, index} ->
      case metadata_value(test_case.metadata, field) do
        {:ok, value} when is_binary(value) or is_number(value) or is_boolean(value) ->
          :ok

        {:ok, nil} ->
          raise ArgumentError, "case #{index} is missing metadata group #{inspect(field)}"

        {:ok, value} ->
          raise ArgumentError,
                "case #{index} metadata group #{inspect(field)} must be a string, number, or boolean; got: #{inspect(value)}"

        {:error, :ambiguous} ->
          raise ArgumentError,
                "case #{index} has conflicting string and atom metadata keys for #{inspect(field)}"
      end
    end)

    :ok
  end

  defp summarize(cases, duration_ms) do
    total = length(cases)
    passed = Enum.count(cases, &(&1.status == :passed))
    errors = Enum.count(cases, &Map.get(&1, :execution_error, false))
    attempts = Enum.flat_map(cases, &Map.get(&1, :attempts, [&1]))
    attempt_passed = Enum.count(attempts, &(&1.status == :passed))
    attempt_errors = Enum.count(attempts, &Map.get(&1, :execution_error, false))

    %{
      total: total,
      passed: passed,
      failed: total - passed,
      errors: errors,
      pass_rate: rate(passed, total),
      duration_ms: duration_ms,
      attempts: %{
        total: length(attempts),
        passed: attempt_passed,
        failed: length(attempts) - attempt_passed,
        errors: attempt_errors,
        pass_rate: rate(attempt_passed, length(attempts))
      }
    }
  end

  defp aggregate_metrics(cases) do
    cases
    |> Enum.flat_map(&Map.get(&1, :attempts, [&1]))
    |> Enum.flat_map(fn attempt ->
      Enum.map(attempt.evaluations, fn {type, result} ->
        {type, assertion_status(result)}
      end)
    end)
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
    |> Map.new(fn {type, statuses} ->
      total = length(statuses)
      passed = Enum.count(statuses, &(&1 == :passed))
      errors = Enum.count(statuses, &(&1 == :error))

      {type,
       %{
         total: total,
         passed: passed,
         failed: total - passed,
         errors: errors,
         pass_rate: rate(passed, total)
       }}
    end)
  end

  defp assertion_status({:pass, _details}), do: :passed
  defp assertion_status({:fail, _details}), do: :failed
  defp assertion_status(_result), do: :error

  defp overall_gate(_summary, nil), do: nil

  defp overall_gate(summary, threshold) do
    %{
      threshold: threshold,
      total: summary.total,
      passed: summary.passed,
      failed: summary.failed,
      errors: summary.errors,
      pass_rate: summary.pass_rate,
      passed_gate: summary.errors == 0 and summary.total > 0 and summary.pass_rate >= threshold
    }
  end

  defp group_gates(_cases, nil), do: nil

  defp group_gates(cases, %{by: field, pass_rate: threshold}) do
    results =
      cases
      |> Enum.group_by(fn result ->
        {:ok, value} = metadata_value(result.metadata, field)
        value
      end)
      |> Enum.map(fn {value, group_cases} ->
        total = length(group_cases)
        passed = Enum.count(group_cases, &(&1.status == :passed))
        errors = Enum.count(group_cases, & &1.execution_error)

        %{
          value: value,
          threshold: threshold,
          total: total,
          passed: passed,
          failed: total - passed,
          errors: errors,
          pass_rate: rate(passed, total),
          passed_gate: errors == 0 and passed / total >= threshold
        }
      end)
      |> Enum.sort_by(&inspect(&1.value))

    %{by: field, threshold: threshold, results: results}
  end

  defp gate_passed?(nil), do: true
  defp gate_passed?(gate), do: gate.passed_gate
  defp groups_passed?(nil), do: true
  defp groups_passed?(groups), do: Enum.all?(groups.results, & &1.passed_gate)

  defp metadata_value(metadata, field) when is_map(metadata) do
    string_key = to_string(field)

    values =
      Enum.flat_map(metadata, fn
        {key, value} when is_binary(key) ->
          if key == string_key, do: [value], else: []

        {key, value} when is_atom(key) ->
          if Atom.to_string(key) == string_key, do: [value], else: []

        {_key, _value} ->
          []
      end)
      |> Enum.uniq()

    case values do
      [] -> {:ok, nil}
      [value] -> {:ok, value}
      _values -> {:error, :ambiguous}
    end
  end

  defp metadata_value(_metadata, _field), do: {:ok, nil}

  defp rate(_passed, 0), do: 0.0
  defp rate(passed, total), do: passed / total
end
