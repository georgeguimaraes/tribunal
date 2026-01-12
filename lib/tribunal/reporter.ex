defmodule Tribunal.Reporter do
  @moduledoc """
  Behaviour for eval result reporters.
  """

  @type results :: %{
          summary: %{
            total: non_neg_integer(),
            passed: non_neg_integer(),
            failed: non_neg_integer(),
            pass_rate: float(),
            duration_ms: non_neg_integer()
          },
          metrics: %{atom() => %{passed: non_neg_integer(), total: non_neg_integer()}},
          cases: [map()]
        }

  @callback format(results()) :: String.t()
end

defmodule Tribunal.Reporter.Console do
  @moduledoc """
  Pretty console output for eval results.
  """

  @behaviour Tribunal.Reporter

  @impl true
  def format(results) do
    [
      header(),
      summary_section(results.summary),
      metrics_section(results.metrics),
      failures_section(results.cases),
      footer(results.summary)
    ]
    |> Enum.join("\n")
  end

  defp header do
    """

    Tribunal LLM Evaluation
    ═══════════════════════════════════════════════════════════════
    """
  end

  defp summary_section(summary) do
    """
    Summary
    ───────────────────────────────────────────────────────────────
      Total:     #{summary.total} test cases
      Passed:    #{summary.passed} (#{round(summary.pass_rate * 100)}%)
      Failed:    #{summary.failed}
      Duration:  #{format_duration(summary.duration_ms)}
    """
  end

  defp metrics_section(metrics) when map_size(metrics) == 0, do: ""

  defp metrics_section(metrics) do
    rows =
      Enum.map_join(metrics, "\n", fn {name, data} ->
        rate = if data.total > 0, do: data.passed / data.total, else: 0
        bar = progress_bar(rate, 20)
        "  #{pad(name, 14)} #{data.passed}/#{data.total} passed   #{round(rate * 100)}%   #{bar}"
      end)

    """
    Results by Metric
    ───────────────────────────────────────────────────────────────
    #{rows}
    """
  end

  defp failures_section(cases) do
    failures = Enum.filter(cases, &(&1.status == :failed))

    if Enum.empty?(failures) do
      ""
    else
      rows =
        failures
        |> Enum.with_index(1)
        |> Enum.map_join("\n", &format_failure_row/1)

      """
      Failed Cases
      ───────────────────────────────────────────────────────────────
      #{rows}
      """
    end
  end

  defp format_failure_row({c, idx}) do
    input = String.slice(c.input, 0, 50)

    reasons =
      Enum.map_join(c.failures, "\n", fn {type, reason} -> "     ├─ #{type}: #{reason}" end)

    """
      #{idx}. "#{input}"
    #{reasons}
    """
  end

  defp footer(summary) do
    status = if summary.failed > 0, do: "❌ FAILED", else: "✅ PASSED"

    """
    ───────────────────────────────────────────────────────────────
    #{status}
    """
  end

  defp progress_bar(rate, width) do
    filled = round(rate * width)
    empty = width - filled
    String.duplicate("█", filled) <> String.duplicate("░", empty)
  end

  defp pad(term, width) do
    str = to_string(term)
    String.pad_trailing(str, width)
  end

  defp format_duration(ms) when ms < 1000, do: "#{ms}ms"
  defp format_duration(ms), do: "#{Float.round(ms / 1000, 1)}s"
end

defmodule Tribunal.Reporter.JSON do
  @moduledoc """
  JSON output for CI/machine consumption.
  """

  @behaviour Tribunal.Reporter

  @impl true
  def format(results) do
    results
    |> convert_for_json()
    |> JSON.encode!()
  end

  defp convert_for_json(data) when is_map(data) do
    Map.new(data, fn {k, v} ->
      key = if is_atom(k), do: Atom.to_string(k), else: k
      {key, convert_for_json(v)}
    end)
  end

  defp convert_for_json(data) when is_list(data) do
    Enum.map(data, &convert_for_json/1)
  end

  # Convert tuples to maps (for failures like {:faithful, "reason"})
  defp convert_for_json({k, v}) when is_atom(k) do
    %{Atom.to_string(k) => convert_for_json(v)}
  end

  defp convert_for_json({k, v}) when is_binary(k) do
    %{k => convert_for_json(v)}
  end

  defp convert_for_json(data) when is_atom(data) and data not in [nil, true, false] do
    Atom.to_string(data)
  end

  defp convert_for_json(data), do: data
end

defmodule Tribunal.Reporter.GitHub do
  @moduledoc """
  GitHub Actions annotations format.
  """

  @behaviour Tribunal.Reporter

  @impl true
  def format(results) do
    annotations =
      results.cases
      |> Enum.filter(&(&1.status == :failed))
      |> Enum.map(fn c ->
        reasons = Enum.map_join(c.failures, "; ", fn {type, reason} -> "#{type}: #{reason}" end)
        "::error::#{c.input}: #{reasons}"
      end)

    summary =
      "::notice::Tribunal: #{results.summary.passed}/#{results.summary.total} passed (#{round(results.summary.pass_rate * 100)}%)"

    (annotations ++ [summary])
    |> Enum.join("\n")
  end
end

defmodule Tribunal.Reporter.JUnit do
  @moduledoc """
  JUnit XML format for CI tools.
  """

  @behaviour Tribunal.Reporter

  @impl true
  def format(results) do
    test_cases = Enum.map_join(results.cases, "\n", &format_testcase/1)

    """
    <?xml version="1.0" encoding="UTF-8"?>
    <testsuites name="Tribunal" tests="#{results.summary.total}" failures="#{results.summary.failed}" time="#{results.summary.duration_ms / 1000}">
      <testsuite name="eval" tests="#{results.summary.total}" failures="#{results.summary.failed}">
    #{test_cases}
      </testsuite>
    </testsuites>
    """
  end

  defp format_testcase(%{status: :passed} = c) do
    name = escape_xml(c.input)
    time = (c.duration_ms || 0) / 1000
    ~s(    <testcase name="#{name}" time="#{time}"/>)
  end

  defp format_testcase(c) do
    name = escape_xml(c.input)
    time = (c.duration_ms || 0) / 1000

    failure_msg =
      c.failures
      |> Enum.map_join("\n", fn {type, reason} -> "#{type}: #{reason}" end)
      |> escape_xml()

    """
        <testcase name="#{name}" time="#{time}">
          <failure message="Assertion failed">#{failure_msg}</failure>
        </testcase>
    """
  end

  defp escape_xml(str) do
    str
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
    |> String.replace("\"", "&quot;")
    |> String.replace("'", "&apos;")
  end
end
