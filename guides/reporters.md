# Reporters

Tribunal provides multiple output formats for evaluation results, suitable for different environments: local development, CI/CD pipelines, and tooling integration.

## Available Reporters

| Reporter | Use Case |
|----------|----------|
| Console | Local development, human-readable output with unicode |
| Text | Plain ASCII output, no unicode (for limited terminals) |
| JSON | Machine-readable, tooling integration |
| HTML | Shareable reports, dashboards |
| GitHub | GitHub Actions annotations |
| JUnit | CI/CD systems (Jenkins, CircleCI, etc.) |

## Console Reporter

Default reporter with colored, human-readable output.

```elixir
alias Tribunal.Reporter.Console

report = %{
  summary: %{
    total: 10,
    passed: 8,
    failed: 2,
    pass_rate: 80.0,
    duration_ms: 1500
  },
  metrics: %{
    contains: %{passed: 5, total: 5},
    faithful: %{passed: 3, total: 5}
  },
  cases: [
    %{input: "What is X?", status: :passed, failures: [], duration_ms: 100},
    %{input: "How do I Y?", status: :failed, failures: [{:faithful, "Not grounded"}], duration_ms: 200}
  ]
}

Console.format(report)
```

Output:
```
═══════════════════════════════════════════════════════════════════
                    Tribunal LLM Evaluation
═══════════════════════════════════════════════════════════════════

Summary
───────────────────────────────────────────────────────────────────
Total: 10 | Passed: 8 | Failed: 2 | Pass Rate: 80.0% | Duration: 1.5s

Metrics by Assertion Type
───────────────────────────────────────────────────────────────────
contains        5/5   100.0% ████████████████████
faithful        3/5    60.0% ████████████

Failed Cases
───────────────────────────────────────────────────────────────────
Input: How do I Y?
  ✗ faithful: Not grounded

═══════════════════════════════════════════════════════════════════
                         ❌ FAILED
═══════════════════════════════════════════════════════════════════
```

## Text Reporter

Plain ASCII output without unicode characters. Use when your terminal or environment doesn't support unicode.

```bash
mix tribunal.eval --format text
```

Output:
```
Tribunal LLM Evaluation
===================================================================

Summary
-------------------------------------------------------------------
Total: 10 | Passed: 8 | Failed: 2 | Pass Rate: 80% | Duration: 1.5s

Metrics by Assertion Type
-------------------------------------------------------------------
contains        5/5   100%  ####################
faithful        3/5    60%  ############--------

Failed Cases
-------------------------------------------------------------------
Input: How do I Y?
  |- faithful: Not grounded

-------------------------------------------------------------------
FAILED
```

Key differences from Console:
- Uses `===` and `---` instead of `═══` and `───`
- Uses `#` and `-` for progress bars instead of `█` and `░`
- Uses `PASSED`/`FAILED` instead of `✅`/`❌`
- Uses `|-` instead of `├─` for failure trees

## JSON Reporter

Machine-readable JSON output.

```elixir
alias Tribunal.Reporter.JSON

output = JSON.format(report)
# Returns JSON string
```

Output:
```json
{
  "summary": {
    "total": 10,
    "passed": 8,
    "failed": 2,
    "pass_rate": 80.0,
    "duration_ms": 1500
  },
  "metrics": {
    "contains": {"passed": 5, "total": 5},
    "faithful": {"passed": 3, "total": 5}
  },
  "cases": [
    {
      "input": "What is X?",
      "status": "passed",
      "failures": [],
      "duration_ms": 100
    },
    {
      "input": "How do I Y?",
      "status": "failed",
      "failures": [["faithful", "Not grounded"]],
      "duration_ms": 200
    }
  ]
}
```

## HTML Reporter

Self-contained HTML report with embedded CSS. Great for sharing results or building dashboards.

```bash
mix tribunal.eval --format html --output report.html
```

Features:
- Self-contained (no external dependencies)
- Color-coded metrics (green ≥90%, yellow ≥70%, red <70%)
- Visual progress bars
- Responsive design
- Failed cases with details

```elixir
alias Tribunal.Reporter.HTML

output = HTML.format(report)
File.write!("report.html", output)
```

The HTML report includes:
- Summary stats grid (total, passed, failed, pass rate, duration)
- Metrics table with visual progress bars
- Failed cases section with failure reasons
- Overall pass/fail status banner

## GitHub Reporter

Outputs GitHub Actions workflow annotations.

```elixir
alias Tribunal.Reporter.GitHub

output = GitHub.format(report)
```

Output:
```
::error::Evaluation failed: faithful - Not grounded (Input: How do I Y?)
::notice::Tribunal Evaluation: 8/10 passed (80.0%)
```

In GitHub Actions, these appear as:
- Red error annotations for failures
- Notice annotations for the summary

## JUnit Reporter

XML format compatible with most CI/CD systems.

```elixir
alias Tribunal.Reporter.JUnit

output = JUnit.format(report)
```

Output:
```xml
<?xml version="1.0" encoding="UTF-8"?>
<testsuites name="Tribunal Evaluation" tests="10" failures="2" time="1.5">
  <testsuite name="LLM Evaluation" tests="10" failures="2" time="1.5">
    <testcase name="What is X?" time="0.1"/>
    <testcase name="How do I Y?" time="0.2">
      <failure message="faithful: Not grounded"/>
    </testcase>
  </testsuite>
</testsuites>
```

## CLI Usage

Use reporters from the command line:

```bash
# Console (default, with unicode)
mix tribunal.eval

# Text (plain ASCII, no unicode)
mix tribunal.eval --format text

# JSON
mix tribunal.eval --format json

# JSON to file
mix tribunal.eval --format json --output results.json

# HTML report
mix tribunal.eval --format html --output report.html

# GitHub Actions
mix tribunal.eval --format github

# JUnit
mix tribunal.eval --format junit --output junit.xml
```

## GitHub Actions Example

```yaml
# .github/workflows/eval.yml
name: LLM Evaluation

on: [push, pull_request]

jobs:
  eval:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Setup Elixir
        uses: erlef/setup-beam@v1
        with:
          elixir-version: '1.16'
          otp-version: '26'

      - name: Install dependencies
        run: mix deps.get

      - name: Run evaluations
        run: mix tribunal.eval --format github
        env:
          ANTHROPIC_API_KEY: ${{ secrets.ANTHROPIC_API_KEY }}
```

## CI/CD with JUnit

Most CI systems can parse JUnit XML for test reporting:

```yaml
# CircleCI example
jobs:
  eval:
    steps:
      - run:
          name: Run evaluations
          command: mix tribunal.eval --format junit --output test-results/tribunal.xml
      - store_test_results:
          path: test-results
```

## Programmatic Usage

Build report data and format:

```elixir
alias Tribunal.{Dataset, Assertions, Reporter}

# Run evaluations
{:ok, items} = Dataset.load_with_assertions("test/evals/datasets/questions.json")

start_time = System.monotonic_time(:millisecond)

case_results = Enum.map(items, fn {test_case, assertions} ->
  case_start = System.monotonic_time(:millisecond)

  output = MyApp.query(test_case.input)
  test_case = %{test_case | actual_output: output}

  results = Tribunal.evaluate(test_case, assertions)
  failures = extract_failures(results)

  %{
    input: test_case.input,
    status: if(Assertions.all_passed?(results), do: :passed, else: :failed),
    failures: failures,
    duration_ms: System.monotonic_time(:millisecond) - case_start
  }
end)

duration_ms = System.monotonic_time(:millisecond) - start_time

# Build report
passed = Enum.count(case_results, &(&1.status == :passed))
total = length(case_results)

report = %{
  summary: %{
    total: total,
    passed: passed,
    failed: total - passed,
    pass_rate: passed / total * 100,
    duration_ms: duration_ms
  },
  metrics: build_metrics(case_results),
  cases: case_results
}

# Output in desired format
case System.get_env("OUTPUT_FORMAT", "console") do
  "text" -> Reporter.Text.format(report)
  "json" -> Reporter.JSON.format(report)
  "html" -> Reporter.HTML.format(report)
  "github" -> Reporter.GitHub.format(report)
  "junit" -> Reporter.JUnit.format(report)
  _ -> Reporter.Console.format(report)
end
```

## Report Data Structure

All reporters expect this structure:

```elixir
%{
  summary: %{
    total: integer(),       # Total test cases
    passed: integer(),      # Passing cases
    failed: integer(),      # Failing cases
    pass_rate: float(),     # Percentage (0-100)
    duration_ms: integer()  # Total duration
  },
  metrics: %{
    assertion_type => %{
      passed: integer(),
      total: integer()
    }
  },
  cases: [
    %{
      input: String.t(),
      status: :passed | :failed,
      failures: [{atom(), String.t()}],  # [{type, reason}, ...]
      duration_ms: integer()
    }
  ]
}
```
