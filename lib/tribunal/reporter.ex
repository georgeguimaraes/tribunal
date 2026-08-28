defmodule Tribunal.Reporter do
  @moduledoc """
  Behaviour for eval result reporters.
  """

  @type results :: %{
          schema_version: pos_integer(),
          summary: %{
            total: non_neg_integer(),
            passed: non_neg_integer(),
            failed: non_neg_integer(),
            errors: non_neg_integer(),
            pass_rate: float(),
            duration_ms: non_neg_integer()
          },
          metrics: %{
            (atom() | String.t()) => %{
              passed: non_neg_integer(),
              failed: non_neg_integer(),
              errors: non_neg_integer(),
              total: non_neg_integer(),
              pass_rate: float()
            }
          },
          cases: [map()]
        }

  @callback format(results()) :: String.t()
end

defmodule Tribunal.Reporter.Format do
  @moduledoc false

  alias Tribunal.TestCase

  def input(case_result), do: case_result |> Map.fetch!(:input) |> TestCase.display_input()

  def value(value) when is_binary(value), do: value
  def value(value), do: TestCase.display_input(value)

  def sample(case_result) do
    case Map.get(case_result, :sample) do
      %{repeat: repeat, passed: passed, failed: failed, errors: errors, pass_rule: pass_rule} ->
        error_label = if errors == 1, do: "error", else: "errors"

        "samples: #{passed}/#{repeat} passed, #{failed} failed, #{errors} #{error_label}, " <>
          "rule: #{pass_rule(pass_rule)}"

      _other ->
        nil
    end
  end

  def outcome_counts(summary) do
    errors = Map.get(summary, :errors, 0)
    %{failures: max(summary.failed - errors, 0), errors: errors}
  end

  def gates(%{overall: overall, groups: groups}) do
    [overall_gate(overall), group_gates(groups)]
    |> Enum.reject(&is_nil/1)
    |> List.flatten()
  end

  def gates(_gates), do: []

  defp overall_gate(nil), do: nil

  defp overall_gate(gate) do
    "overall: #{percent(gate.pass_rate)} observed, #{percent(gate.threshold)} required, " <>
      gate_status(gate.passed_gate)
  end

  defp group_gates(nil), do: nil

  defp group_gates(groups) do
    Enum.map(groups.results, fn result ->
      "#{groups.by}=#{value(result.value)}: #{percent(result.pass_rate)} observed, " <>
        "#{percent(result.threshold)} required, #{gate_status(result.passed_gate)}"
    end)
  end

  defp percent(rate), do: "#{round(rate * 100)}%"
  defp gate_status(true), do: "passed"
  defp gate_status(false), do: "failed"

  defp pass_rule({:rate, rate}), do: "rate >= #{rate}"
  defp pass_rule(pass_rule), do: to_string(pass_rule)
end

defmodule Tribunal.Reporter.Console do
  @moduledoc """
  Pretty console output for eval results.
  """

  @behaviour Tribunal.Reporter

  alias Tribunal.Reporter.Format

  @impl true
  def format(results) do
    [
      header(),
      summary_section(results.summary),
      gates_section(Map.get(results, :gates)),
      metrics_section(results.metrics),
      outcomes_section(results.cases),
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
    %{failures: failures, errors: errors} = Format.outcome_counts(summary)

    """
    Summary
    ───────────────────────────────────────────────────────────────
      Total:     #{summary.total} test cases
      Passed:    #{summary.passed} (#{round(summary.pass_rate * 100)}%)
      Failed:    #{failures}
      Errors:    #{errors}
      Duration:  #{format_duration(summary.duration_ms)}
    """
  end

  defp gates_section(gates) do
    case Format.gates(gates) do
      [] ->
        ""

      rows ->
        "Gates\n───────────────────────────────────────────────────────────────\n" <>
          Enum.map_join(rows, "\n", &("  " <> &1)) <> "\n"
    end
  end

  defp metrics_section(metrics) when map_size(metrics) == 0, do: ""

  defp metrics_section(metrics) do
    rows =
      Enum.map_join(metrics, "\n", fn {name, data} ->
        rate = if data.total > 0, do: data.passed / data.total, else: 0
        bar = progress_bar(rate, 20)
        counts = String.pad_leading("#{data.passed}/#{data.total}", 7)
        pct = String.pad_leading("#{round(rate * 100)}%", 4)
        "  #{pad(name, 14)} #{counts} passed  #{pct}  #{bar}"
      end)

    """
    Results by Metric
    ───────────────────────────────────────────────────────────────
    #{rows}
    """
  end

  defp outcomes_section(cases) do
    failures =
      Enum.filter(cases, &(&1.status == :failed and not Map.get(&1, :execution_error, false)))

    errors = Enum.filter(cases, &Map.get(&1, :execution_error, false))

    [case_section("Failed Cases", failures), case_section("Errors", errors)]
  end

  defp case_section(_title, []), do: ""

  defp case_section(title, cases) do
    rows =
      cases
      |> Enum.with_index(1)
      |> Enum.map_join("\n", &format_failure_row/1)

    """
    #{title}
    ───────────────────────────────────────────────────────────────
    #{rows}
    """
  end

  defp format_failure_row({c, idx}) do
    input = Format.input(c)

    reasons =
      Enum.map_join(c.failures, "\n", fn {type, reason} -> "     ├─ #{type}: #{reason}" end)

    sample_line = if sample = Format.sample(c), do: "\n     ├─ #{sample}", else: ""

    output_line =
      if c[:actual_output] do
        output = c.actual_output |> Format.value() |> String.slice(0, 200)
        "\n     └─ output: #{output}"
      else
        ""
      end

    """
      #{idx}. "#{input}"
    #{reasons}#{sample_line}#{output_line}
    """
  end

  defp footer(summary) do
    status =
      case Map.get(summary, :gate_status) do
        status when status in [:error, :failed] -> "❌ FAILED"
        :passed -> "✅ PASSED"
        :not_configured -> "✅ COMPLETED (no gate)"
        _ -> legacy_console_status(summary)
      end

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

  defp legacy_console_status(summary) do
    case Map.get(summary, :threshold_passed, summary.failed == 0) do
      nil -> "✅ COMPLETED (no gate)"
      true -> "✅ PASSED"
      false -> "❌ FAILED"
    end
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

  alias Tribunal.Reporter.Format

  @impl true
  def format(results) do
    [
      header(),
      summary_section(results.summary),
      gates_section(Map.get(results, :gates)),
      metrics_section(results.metrics),
      outcomes_section(results.cases),
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
    %{failures: failures, errors: errors} = Format.outcome_counts(summary)

    """
    Summary
    -------------------------------------------------------------------
      Total:     #{summary.total} test cases
      Passed:    #{summary.passed} (#{round(summary.pass_rate * 100)}%)
      Failed:    #{failures}
      Errors:    #{errors}
      Duration:  #{format_duration(summary.duration_ms)}
    """
  end

  defp gates_section(gates) do
    case Format.gates(gates) do
      [] ->
        ""

      rows ->
        "Gates\n-------------------------------------------------------------------\n" <>
          Enum.map_join(rows, "\n", &("  " <> &1)) <> "\n"
    end
  end

  defp metrics_section(metrics) when map_size(metrics) == 0, do: ""

  defp metrics_section(metrics) do
    rows =
      Enum.map_join(metrics, "\n", fn {name, data} ->
        rate = if data.total > 0, do: data.passed / data.total, else: 0
        bar = progress_bar(rate, 20)
        counts = String.pad_leading("#{data.passed}/#{data.total}", 7)
        pct = String.pad_leading("#{round(rate * 100)}%", 4)
        "  #{pad(name, 14)} #{counts} passed  #{pct}  #{bar}"
      end)

    """
    Results by Metric
    -------------------------------------------------------------------
    #{rows}
    """
  end

  defp outcomes_section(cases) do
    failures =
      Enum.filter(cases, &(&1.status == :failed and not Map.get(&1, :execution_error, false)))

    errors = Enum.filter(cases, &Map.get(&1, :execution_error, false))

    [case_section("Failed Cases", failures), case_section("Errors", errors)]
  end

  defp case_section(_title, []), do: ""

  defp case_section(title, cases) do
    rows =
      cases
      |> Enum.with_index(1)
      |> Enum.map_join("\n", &format_failure_row/1)

    """
    #{title}
    -------------------------------------------------------------------
    #{rows}
    """
  end

  defp format_failure_row({c, idx}) do
    input = Format.input(c)

    reasons =
      Enum.map_join(c.failures, "\n", fn {type, reason} -> "     |- #{type}: #{reason}" end)

    sample_line = if sample = Format.sample(c), do: "\n     |- #{sample}", else: ""

    output_line =
      if c[:actual_output] do
        output = c.actual_output |> Format.value() |> String.slice(0, 200)
        "\n     \\- output: #{output}"
      else
        ""
      end

    """
      #{idx}. "#{input}"
    #{reasons}#{sample_line}#{output_line}
    """
  end

  defp footer(summary) do
    status =
      case Map.get(summary, :gate_status) do
        status when status in [:error, :failed] -> "FAILED"
        :passed -> "PASSED"
        :not_configured -> "COMPLETED (no gate)"
        _ -> legacy_text_status(summary)
      end

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

  defp legacy_text_status(summary) do
    case Map.get(summary, :threshold_passed, summary.failed == 0) do
      nil -> "COMPLETED (no gate)"
      true -> "PASSED"
      false -> "FAILED"
    end
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
    |> Map.put(:schema_version, 3)
    |> convert_for_json()
    |> JSON.encode!()
  end

  defp convert_for_json(data) when is_map(data) do
    Map.new(data, fn {k, v} ->
      key = if is_atom(k), do: Atom.to_string(k), else: k
      value = if key == "evaluations", do: convert_evaluations(v), else: convert_for_json(v)
      {key, value}
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

  defp convert_evaluations(evaluations) when is_list(evaluations) do
    Enum.map(evaluations, fn
      {type, result} ->
        %{
          "type" => convert_for_json(type),
          "result" => convert_for_json(result)
        }

      evaluation ->
        convert_for_json(evaluation)
    end)
  end

  defp convert_evaluations(evaluations), do: convert_for_json(evaluations)
end

defmodule Tribunal.Reporter.GitHub do
  @moduledoc """
  GitHub Actions annotations format.
  """

  @behaviour Tribunal.Reporter

  alias Tribunal.Reporter.Format

  @impl true
  def format(results) do
    annotations =
      results.cases
      |> Enum.filter(&(&1.status == :failed))
      |> Enum.map(fn c ->
        reasons = Enum.map_join(c.failures, "; ", fn {type, reason} -> "#{type}: #{reason}" end)
        sample_suffix = if sample = Format.sample(c), do: " | #{sample}", else: ""

        output_suffix =
          if c[:actual_output], do: " | output: #{Format.value(c.actual_output)}", else: ""

        message = "#{Format.input(c)}: #{reasons}#{sample_suffix}#{output_suffix}"
        "::error::#{escape_command_data(message)}"
      end)

    summary_text =
      "Tribunal: #{results.summary.passed}/#{results.summary.total} passed " <>
        "(#{round(results.summary.pass_rate * 100)}%)"

    summary = "::notice::#{escape_command_data(summary_text)}"

    (annotations ++ [summary])
    |> Enum.join("\n")
  end

  defp escape_command_data(data) do
    data
    |> String.replace("%", "%25")
    |> String.replace("\r", "%0D")
    |> String.replace("\n", "%0A")
  end
end

defmodule Tribunal.Reporter.JUnit do
  @moduledoc """
  JUnit XML format for CI tools.
  """

  @behaviour Tribunal.Reporter

  alias Tribunal.Reporter.Format

  @impl true
  def format(results) do
    cases = results.cases
    tests = length(cases)
    errors = Enum.count(cases, &Map.get(&1, :execution_error, false))

    failures =
      Enum.count(cases, fn case_result ->
        case_result.status == :failed and not Map.get(case_result, :execution_error, false)
      end)

    test_cases = Enum.map_join(cases, "\n", &format_testcase/1)
    time = results.summary.duration_ms / 1000

    """
    <?xml version="1.0" encoding="UTF-8"?>
    <testsuites name="Tribunal" tests="#{tests}" failures="#{failures}" errors="#{errors}" time="#{time}">
      <testsuite name="eval" tests="#{tests}" failures="#{failures}" errors="#{errors}" time="#{time}">
    #{test_cases}
      </testsuite>
    </testsuites>
    """
  end

  defp format_testcase(%{execution_error: true} = c) do
    format_failed_testcase(c, "error", "Operational error")
  end

  defp format_testcase(%{status: :passed} = c) do
    name = c |> Format.input() |> escape_xml()
    time = (c.duration_ms || 0) / 1000
    ~s(    <testcase name="#{name}" time="#{time}"/>)
  end

  defp format_testcase(c) do
    format_failed_testcase(c, "failure", "Assertion failed")
  end

  defp format_failed_testcase(c, element, message) do
    name = c |> Format.input() |> escape_xml()
    time = (c.duration_ms || 0) / 1000
    details = c |> failure_details() |> escape_xml()

    """
        <testcase name="#{name}" time="#{time}">
          <#{element} message="#{message}">#{details}</#{element}>
        </testcase>
    """
  end

  defp failure_details(c) do
    reasons = Enum.map_join(c.failures, "\n", fn {type, reason} -> "#{type}: #{reason}" end)
    sample_line = if sample = Format.sample(c), do: "\n#{sample}", else: ""

    output_line =
      if c[:actual_output], do: "\nOutput: #{Format.value(c.actual_output)}", else: ""

    reasons <> sample_line <> output_line
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

  alias Tribunal.Reporter.Format

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
        .status.completed { background: #e2e3e5; color: #383d41; }
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
        #{gates_section(Map.get(results, :gates))}
        #{metrics_section(results.metrics)}
        #{outcomes_section(results.cases)}
        <div class="footer">Generated by Tribunal</div>
      </div>
    </body>
    </html>
    """
  end

  defp summary_section(summary) do
    %{failures: failures, errors: errors} = Format.outcome_counts(summary)

    {status_class, status_text} =
      case Map.get(summary, :gate_status) do
        status when status in [:error, :failed] -> {"failed", "FAILED"}
        :passed -> {"passed", "PASSED"}
        :not_configured -> {"completed", "COMPLETED (no gate)"}
        _ -> legacy_html_status(summary)
      end

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
          <div class="stat-value">#{failures}</div>
          <div class="stat-label">Failed</div>
        </div>
        <div class="stat">
          <div class="stat-value">#{errors}</div>
          <div class="stat-label">Errors</div>
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

  defp legacy_html_status(summary) do
    case Map.get(summary, :threshold_passed, summary.failed == 0) do
      nil -> {"completed", "COMPLETED (no gate)"}
      true -> {"passed", "PASSED"}
      false -> {"failed", "FAILED"}
    end
  end

  defp gates_section(gates) do
    case Format.gates(gates) do
      [] ->
        ""

      rows ->
        items = Enum.map_join(rows, "", &"<li>#{escape_html(&1)}</li>")
        ~s(<div class="metrics"><h2>Gates</h2><ul>#{items}</ul></div>)
    end
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

  defp outcomes_section(cases) do
    failures =
      Enum.filter(cases, &(&1.status == :failed and not Map.get(&1, :execution_error, false)))

    errors = Enum.filter(cases, &Map.get(&1, :execution_error, false))

    [
      case_section("failures", "Failed Cases", failures),
      case_section("failures errors", "Errors", errors)
    ]
  end

  defp case_section(_class, _title, []), do: ""

  defp case_section(class, title, cases) do
    rows = Enum.map_join(cases, "\n", &format_failure_row/1)

    """
    <div class="#{class}">
      <h2>#{title}</h2>
      #{rows}
    </div>
    """
  end

  defp format_failure_row(c) do
    input = Format.input(c)

    reasons =
      Enum.map_join(c.failures, "<br>", fn {type, reason} ->
        "<code>#{escape_html(to_string(type))}</code>: #{escape_html(reason)}"
      end)

    sample_html =
      if sample = Format.sample(c) do
        ~s(<div class="failure-sample">#{escape_html(sample)}</div>)
      else
        ""
      end

    output_html =
      if c[:actual_output] do
        output = c.actual_output |> Format.value() |> escape_html()
        ~s(<div class="failure-output"><strong>Output:</strong> #{output}</div>)
      else
        ""
      end

    """
    <div class="failure">
      <div class="failure-input">#{escape_html(input)}</div>
      <div class="failure-reason">#{reasons}</div>
      #{sample_html}
      #{output_html}
    </div>
    """
  end

  defp escape_html(str) do
    str
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
    |> String.replace("\"", "&quot;")
    |> String.replace("'", "&#39;")
  end

  defp format_duration(ms) when ms < 1000, do: "#{ms}ms"
  defp format_duration(ms), do: "#{Float.round(ms / 1000, 1)}s"
end
