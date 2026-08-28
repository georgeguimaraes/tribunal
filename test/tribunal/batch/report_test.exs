defmodule Tribunal.Batch.ReportTest do
  use ExUnit.Case, async: true

  alias Tribunal.Batch.Report
  alias Tribunal.TestCase

  test "aggregates reduced cases and attempt-based metrics separately" do
    report = Report.build([sampled_case()], System.monotonic_time(:millisecond))

    assert %{total: 1, passed: 1, failed: 0, errors: 0} = report.summary
    assert %{total: 2, passed: 1, failed: 1, errors: 0} = report.summary.attempts

    assert %{total: 2, passed: 1, failed: 1, errors: 0, pass_rate: 0.5} =
             report.metrics.contains
  end

  test "applies overall and observed group gates to reduced cases" do
    cases = [sampled_case(), failed_case("edge")]
    report = Report.build(cases, System.monotonic_time(:millisecond))

    {report, passed?} =
      Report.apply_gates(report, %{
        overall: 0.5,
        groups: %{by: "kind", pass_rate: 0.5}
      })

    refute passed?
    assert report.summary.gate_status == :failed
    assert report.gates.overall.passed_gate
    assert Enum.find(report.gates.groups.results, &(&1.value == "edge")).passed_gate == false
  end

  test "an operational case makes configured gates error" do
    report = Report.build([failed_case("edge", true)], System.monotonic_time(:millisecond))
    {report, passed?} = Report.apply_gates(report, %{overall: 0.0})

    refute passed?
    assert report.summary.gate_status == :error
    assert report.summary.threshold_passed == false
  end

  test "rejects missing and ambiguous group metadata before execution" do
    missing = [{%TestCase{input: "query", metadata: %{}}, []}]

    assert_raise ArgumentError, ~r/missing metadata group/, fn ->
      Report.validate_group_cases!(missing, "kind")
    end

    ambiguous = [
      {%TestCase{input: "query", metadata: %{"kind" => "a", kind: "b"}}, []}
    ]

    assert_raise ArgumentError, ~r/conflicting string and atom metadata keys/, fn ->
      Report.validate_group_cases!(ambiguous, :kind)
    end
  end

  defp sampled_case do
    passed = attempt(:passed, "core")
    failed = attempt(:failed, "core")

    passed
    |> Map.put(:attempts, [passed, failed])
    |> Map.put(:sample, %{
      repeat: 2,
      passed: 1,
      failed: 1,
      errors: 0,
      pass_rate: 0.5,
      pass_rule: :any,
      assertions: []
    })
  end

  defp failed_case(kind, execution_error \\ false) do
    attempt(:failed, kind, execution_error)
  end

  defp attempt(status, kind, execution_error \\ false) do
    result = if status == :passed, do: {:pass, %{}}, else: {:fail, %{reason: "miss"}}

    %{
      input: "query",
      metadata: %{"kind" => kind},
      actual_output: "output",
      status: status,
      failures: if(status == :passed, do: [], else: [{:contains, "miss"}]),
      results: %{contains: result},
      evaluations: [{:contains, result}],
      execution_error: execution_error,
      duration_ms: 1
    }
  end
end
