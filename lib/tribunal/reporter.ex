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
    # Use threshold_passed if available (from mix task), otherwise just check failures
    passed = Map.get(summary, :threshold_passed, summary.failed == 0)
    status = if passed, do: "✅ PASSED", else: "❌ FAILED"

    threshold_info =
      cond do
        Map.get(summary, :strict) -> " (strict mode)"
        threshold = Map.get(summary, :threshold) -> " (threshold: #{round(threshold * 100)}%)"
        true -> ""
      end

    """
    ───────────────────────────────────────────────────────────────
    #{status}#{threshold_info}
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

defmodule Tribunal.Reporter.Text do
  @moduledoc """
  Plain ASCII text output (no unicode).
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
    ===================================================================
    """
  end

  defp summary_section(summary) do
    """
    Summary
    -------------------------------------------------------------------
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
    -------------------------------------------------------------------
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
      -------------------------------------------------------------------
      #{rows}
      """
    end
  end

  defp format_failure_row({c, idx}) do
    input = String.slice(c.input, 0, 50)

    reasons =
      Enum.map_join(c.failures, "\n", fn {type, reason} -> "     |- #{type}: #{reason}" end)

    """
      #{idx}. "#{input}"
    #{reasons}
    """
  end

  defp footer(summary) do
    passed = Map.get(summary, :threshold_passed, summary.failed == 0)
    status = if passed, do: "PASSED", else: "FAILED"

    threshold_info =
      cond do
        Map.get(summary, :strict) -> " (strict mode)"
        threshold = Map.get(summary, :threshold) -> " (threshold: #{round(threshold * 100)}%)"
        true -> ""
      end

    """
    -------------------------------------------------------------------
    #{status}#{threshold_info}
    """
  end

  defp progress_bar(rate, width) do
    filled = round(rate * width)
    empty = width - filled
    String.duplicate("#", filled) <> String.duplicate("-", empty)
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

defmodule Tribunal.Reporter.HTML do
  @moduledoc """
  HTML report for shareable results.
  """

  @behaviour Tribunal.Reporter

  @impl true
  def format(results) do
    """
    <!DOCTYPE html>
    <html lang="en">
    <head>
      <meta charset="UTF-8">
      <meta name="viewport" content="width=device-width, initial-scale=1.0">
      <title>Tribunal Evaluation Report</title>
      <style>
        * { box-sizing: border-box; margin: 0; padding: 0; }
        body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; line-height: 1.6; padding: 2rem; background: #f5f5f5; }
        .container { max-width: 900px; margin: 0 auto; }
        h1 { color: #333; margin-bottom: 1.5rem; }
        .summary { background: white; border-radius: 8px; padding: 1.5rem; margin-bottom: 1.5rem; box-shadow: 0 1px 3px rgba(0,0,0,0.1); }
        .summary-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(150px, 1fr)); gap: 1rem; }
        .stat { text-align: center; }
        .stat-value { font-size: 2rem; font-weight: bold; color: #333; }
        .stat-label { color: #666; font-size: 0.9rem; }
        .status { padding: 0.5rem 1rem; border-radius: 4px; display: inline-block; font-weight: bold; margin-top: 1rem; }
        .status.passed { background: #d4edda; color: #155724; }
        .status.failed { background: #f8d7da; color: #721c24; }
        .metrics { background: white; border-radius: 8px; padding: 1.5rem; margin-bottom: 1.5rem; box-shadow: 0 1px 3px rgba(0,0,0,0.1); }
        .metrics h2 { margin-bottom: 1rem; color: #333; font-size: 1.2rem; }
        .metric-row { display: flex; align-items: center; margin-bottom: 0.75rem; }
        .metric-name { width: 120px; font-weight: 500; }
        .metric-bar { flex: 1; height: 20px; background: #e9ecef; border-radius: 4px; overflow: hidden; margin: 0 1rem; }
        .metric-fill { height: 100%; background: #28a745; transition: width 0.3s; }
        .metric-fill.warning { background: #ffc107; }
        .metric-fill.danger { background: #dc3545; }
        .metric-value { width: 100px; text-align: right; font-size: 0.9rem; color: #666; }
        .failures { background: white; border-radius: 8px; padding: 1.5rem; box-shadow: 0 1px 3px rgba(0,0,0,0.1); }
        .failures h2 { margin-bottom: 1rem; color: #333; font-size: 1.2rem; }
        .failure { background: #fff5f5; border-left: 4px solid #dc3545; padding: 1rem; margin-bottom: 1rem; border-radius: 0 4px 4px 0; }
        .failure-input { font-weight: 500; color: #333; margin-bottom: 0.5rem; }
        .failure-reason { color: #666; font-size: 0.9rem; }
        .failure-reason code { background: #f1f1f1; padding: 0.2rem 0.4rem; border-radius: 3px; }
        .footer { text-align: center; margin-top: 2rem; color: #666; font-size: 0.85rem; }
      </style>
    </head>
    <body>
      <div class="container">
        <h1>Tribunal Evaluation Report</h1>
        #{summary_section(results.summary)}
        #{metrics_section(results.metrics)}
        #{failures_section(results.cases)}
        <div class="footer">Generated by Tribunal</div>
      </div>
    </body>
    </html>
    """
  end

  defp summary_section(summary) do
    passed = Map.get(summary, :threshold_passed, summary.failed == 0)
    status_class = if passed, do: "passed", else: "failed"
    status_text = if passed, do: "PASSED", else: "FAILED"

    threshold_info =
      cond do
        Map.get(summary, :strict) -> " (strict mode)"
        threshold = Map.get(summary, :threshold) -> " (threshold: #{round(threshold * 100)}%)"
        true -> ""
      end

    """
    <div class="summary">
      <div class="summary-grid">
        <div class="stat">
          <div class="stat-value">#{summary.total}</div>
          <div class="stat-label">Total Tests</div>
        </div>
        <div class="stat">
          <div class="stat-value">#{summary.passed}</div>
          <div class="stat-label">Passed</div>
        </div>
        <div class="stat">
          <div class="stat-value">#{summary.failed}</div>
          <div class="stat-label">Failed</div>
        </div>
        <div class="stat">
          <div class="stat-value">#{round(summary.pass_rate * 100)}%</div>
          <div class="stat-label">Pass Rate</div>
        </div>
        <div class="stat">
          <div class="stat-value">#{format_duration(summary.duration_ms)}</div>
          <div class="stat-label">Duration</div>
        </div>
      </div>
      <div class="status #{status_class}">#{status_text}#{threshold_info}</div>
    </div>
    """
  end

  defp metrics_section(metrics) when map_size(metrics) == 0, do: ""

  defp metrics_section(metrics) do
    rows = Enum.map_join(metrics, "\n", &format_metric_row/1)

    """
    <div class="metrics">
      <h2>Results by Metric</h2>
      #{rows}
    </div>
    """
  end

  defp format_metric_row({name, data}) do
    rate = if data.total > 0, do: data.passed / data.total, else: 0
    percent = round(rate * 100)

    fill_class =
      cond do
        percent >= 90 -> ""
        percent >= 70 -> "warning"
        true -> "danger"
      end

    """
    <div class="metric-row">
      <div class="metric-name">#{escape_html(to_string(name))}</div>
      <div class="metric-bar">
        <div class="metric-fill #{fill_class}" style="width: #{percent}%"></div>
      </div>
      <div class="metric-value">#{data.passed}/#{data.total} (#{percent}%)</div>
    </div>
    """
  end

  defp failures_section(cases) do
    failures = Enum.filter(cases, &(&1.status == :failed))

    if Enum.empty?(failures) do
      ""
    else
      rows = Enum.map_join(failures, "\n", &format_failure_row/1)

      """
      <div class="failures">
        <h2>Failed Cases</h2>
        #{rows}
      </div>
      """
    end
  end

  defp format_failure_row(c) do
    reasons =
      Enum.map_join(c.failures, "<br>", fn {type, reason} ->
        "<code>#{escape_html(to_string(type))}</code>: #{escape_html(reason)}"
      end)

    """
    <div class="failure">
      <div class="failure-input">#{escape_html(c.input)}</div>
      <div class="failure-reason">#{reasons}</div>
    </div>
    """
  end

  defp escape_html(str) do
    str
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
    |> String.replace("\"", "&quot;")
  end

  defp format_duration(ms) when ms < 1000, do: "#{ms}ms"
  defp format_duration(ms), do: "#{Float.round(ms / 1000, 1)}s"
end
