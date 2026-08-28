# Reporters

`mix tribunal.eval` builds one report and formats it as console, text, JSON, HTML, GitHub annotations, or JUnit XML.

| Format | Option | Use |
|---|---|---|
| Console | `--format console` | Local interactive output, default |
| Text | `--format text` | Plain ASCII logs |
| JSON | `--format json` | Machine processing and stored baselines |
| HTML | `--format html` | Shareable report |
| GitHub | `--format github` | Workflow annotations |
| JUnit | `--format junit` | CI test-report ingestion |

```bash
mix tribunal.eval --format json --output results.json
mix tribunal.eval --format html --output report.html
mix tribunal.eval --format junit --output junit.xml
```

## Status semantics

Report status reflects batch execution and host-owned gates:

| `summary.gate_status` | Meaning | Exit |
|---|---|---|
| `not_configured` | No quality gate, no operational errors | zero |
| `passed` | Every configured overall and group gate passed | zero |
| `failed` | A configured quality gate failed, or zero cases were selected | nonzero |
| `error` | A provider, task, timeout, input, or assertion operation failed | nonzero |

When no quality gate is configured, `summary.threshold_passed` is `null`, including operational-error runs. When a quality gate is configured, it is `true` only when all configured gates pass and `false` otherwise.

Ordinary quality failures are report-only when no gate is configured. Operational errors always fail the command. A permissive sampling rule never hides an operational attempt error.

## JSON schema v3

The JSON reporter emits `schema_version: 3`. A shortened sampled report looks like this:

```json
{
  "schema_version": 3,
  "summary": {
    "total": 1,
    "passed": 0,
    "failed": 1,
    "errors": 0,
    "pass_rate": 0.0,
    "duration_ms": 120,
    "attempts": {
      "total": 3,
      "passed": 2,
      "failed": 1,
      "errors": 0,
      "pass_rate": 0.6666666666666666
    },
    "gate_status": "failed",
    "threshold_passed": false,
    "threshold": 0.9,
    "strict": false
  },
  "gates": {
    "overall": {
      "threshold": 0.9,
      "total": 1,
      "passed": 0,
      "failed": 1,
      "errors": 0,
      "pass_rate": 0.0,
      "passed_gate": false
    },
    "groups": null
  },
  "metrics": {
    "relevant": {
      "total": 3,
      "passed": 2,
      "failed": 1,
      "errors": 0,
      "pass_rate": 0.6666666666666666
    }
  },
  "cases": [
    {
      "input": {"question": "What is the return policy?"},
      "actual_output": "Final attempt output",
      "status": "failed",
      "execution_error": false,
      "duration_ms": 120,
      "sample": {
        "repeat": 3,
        "pass_rule": "all",
        "passed": 2,
        "failed": 1,
        "errors": 0,
        "pass_rate": 0.6666666666666666,
        "assertions": []
      },
      "attempts": [
        {"status": "passed", "execution_error": false},
        {"status": "failed", "execution_error": false},
        {"status": "passed", "execution_error": false}
      ]
    }
  ]
}
```

`summary.total` counts reduced cases. `summary.attempts.total` and metric totals count individual attempts. Repeating five times does not turn five attempts into five independent cases for an overall or group gate.

Each reduced case keeps ordered `attempts` as the authoritative evidence. Its `sample` object records the rule and attempt counts. For repeated cases, top-level `actual_output`, `results`, and `evaluations` are final-attempt compatibility projections, while status, failures, execution error, and duration are reduced across attempts.

`evaluations` preserves assertion execution order and duplicate assertion types. JSON encodes each item as an object with `type` and `result`. `results` is a conservative summary keyed by assertion type, where a failure or error wins over a pass.

Structured inputs remain structured in JSON. Human reporters use a safe JSON representation for names and failure messages.

## Group gates

With `--group-by category --group-threshold 0.8`, `gates.groups` includes the metadata field, threshold, and one result per observed scalar value:

```json
{
  "by": "category",
  "threshold": 0.8,
  "results": [
    {
      "value": "returns",
      "total": 10,
      "passed": 9,
      "failed": 1,
      "errors": 0,
      "pass_rate": 0.9,
      "threshold": 0.8,
      "passed_gate": true
    }
  ]
}
```

Every observed group must pass. Missing or non-scalar group metadata is rejected before execution rather than omitted from the report.

## Human-readable formats

Console and text output show reduced case totals, assertion metrics across attempts, failed cases, sampling counts, and the final gate state. HTML presents the same batch result as a self-contained page. These formats distinguish a completed report-only run from a passed gate.

## GitHub annotations

```bash
mix tribunal.eval --format github
```

Every failed reduced case becomes an `::error::` annotation. Sampling counts and the final projected output are included when available. A final `::notice::` contains the reduced case pass rate.

## JUnit

```bash
mix tribunal.eval --format junit --output junit.xml
```

JUnit emits one testcase per reduced case. Quality failures use `<failure>`. Operational failures use `<error>`. Failure text includes sampling evidence and the final projected output when available.

## Programmatic formatting

The reporter modules format an existing report map:

```elixir
Tribunal.Reporter.Console.format(report)
Tribunal.Reporter.Text.format(report)
Tribunal.Reporter.JSON.format(report)
Tribunal.Reporter.HTML.format(report)
Tribunal.Reporter.GitHub.format(report)
Tribunal.Reporter.JUnit.format(report)
```

The batch builder and gate application used by the Mix task remain internal implementation details. Tribunal does not currently expose a public batch runner.
