# GitHub Actions Integration

Run Tribunal evaluations in your CI/CD pipeline with GitHub Actions.

## Basic Setup

Create `.github/workflows/eval.yml`:

```yaml
name: LLM Evaluation

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

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

## Output Formats for CI

### GitHub Annotations

Use `--format github` for inline PR annotations:

```yaml
- name: Run evaluations
  run: mix tribunal.eval --format github
```

This outputs GitHub workflow commands that create annotations directly on your PR:
- Red error annotations for failed test cases
- Notice annotations for the summary

### Save Reports as Artifacts

Save evaluation results for later review:

```yaml
- name: Run evaluations
  run: |
    mix tribunal.eval --format json --output results.json
    mix tribunal.eval --format html --output report.html

- name: Upload results
  uses: actions/upload-artifact@v4
  with:
    name: eval-results
    path: |
      results.json
      report.html
```

### JUnit for Test Reporting

Use JUnit format for GitHub's built-in test reporting:

```yaml
- name: Run evaluations
  run: mix tribunal.eval --format junit --output results.xml
  continue-on-error: true

- name: Publish test results
  uses: mikepenz/action-junit-report@v4
  if: always()
  with:
    report_paths: 'results.xml'
```

## Pass/Fail Strategies

### Always Pass (Baseline Tracking)

By default, `mix tribunal.eval` exits 0 regardless of results. Use this for tracking baselines without blocking PRs:

```yaml
- name: Run evaluations (tracking only)
  run: mix tribunal.eval --format json --output results.json
  # Always succeeds, results stored for comparison
```

### Threshold-Based Gating

Fail the workflow if pass rate drops below a threshold:

```yaml
- name: Run evaluations
  run: mix tribunal.eval --threshold 0.8 --format github
  # Fails if pass rate < 80%
```

### Strict Mode (Zero Tolerance)

Fail on any test case failure:

```yaml
- name: Run evaluations
  run: mix tribunal.eval --strict --format github
  # Fails if any test case fails
```

## Complete Workflow Examples

### Basic CI Gate

```yaml
name: LLM Evaluation

on:
  pull_request:
    branches: [main]

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

      - name: Cache deps
        uses: actions/cache@v4
        with:
          path: deps
          key: ${{ runner.os }}-mix-${{ hashFiles('**/mix.lock') }}

      - name: Install dependencies
        run: mix deps.get

      - name: Run evaluations
        run: mix tribunal.eval --threshold 0.8 --format github
        env:
          ANTHROPIC_API_KEY: ${{ secrets.ANTHROPIC_API_KEY }}
```

### Full Pipeline with Artifacts

```yaml
name: LLM Evaluation

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

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

      - name: Cache deps
        uses: actions/cache@v4
        with:
          path: deps
          key: ${{ runner.os }}-mix-${{ hashFiles('**/mix.lock') }}

      - name: Install dependencies
        run: mix deps.get

      - name: Run evaluations
        id: eval
        run: |
          mix tribunal.eval --format github --threshold 0.8
          mix tribunal.eval --format json --output results.json
          mix tribunal.eval --format html --output report.html
        env:
          ANTHROPIC_API_KEY: ${{ secrets.ANTHROPIC_API_KEY }}

      - name: Upload results
        uses: actions/upload-artifact@v4
        if: always()
        with:
          name: eval-results-${{ github.sha }}
          path: |
            results.json
            report.html

      - name: Upload JUnit results
        if: always()
        run: mix tribunal.eval --format junit --output junit.xml

      - name: Publish test report
        uses: mikepenz/action-junit-report@v4
        if: always()
        with:
          report_paths: 'junit.xml'
          check_name: 'LLM Evaluation Results'
```

### Parallel Evaluation

Speed up large evaluation suites with concurrency:

```yaml
- name: Run evaluations
  run: mix tribunal.eval --concurrency 10 --format github
  env:
    ANTHROPIC_API_KEY: ${{ secrets.ANTHROPIC_API_KEY }}
```

### Scheduled Baseline Tracking

Run evaluations on a schedule to track model performance over time:

```yaml
name: Scheduled Evaluation

on:
  schedule:
    - cron: '0 6 * * *'  # Daily at 6 AM UTC
  workflow_dispatch:  # Allow manual trigger

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
        run: |
          mix tribunal.eval --format json --output results-$(date +%Y%m%d).json
        env:
          ANTHROPIC_API_KEY: ${{ secrets.ANTHROPIC_API_KEY }}

      - name: Upload results
        uses: actions/upload-artifact@v4
        with:
          name: eval-baseline-${{ github.run_id }}
          path: results-*.json
          retention-days: 90
```

## Environment Variables

Set API keys as repository secrets:

1. Go to Settings > Secrets and variables > Actions
2. Add secrets for your LLM providers:
   - `ANTHROPIC_API_KEY`
   - `OPENAI_API_KEY`
   - etc.

Reference in workflows:

```yaml
env:
  ANTHROPIC_API_KEY: ${{ secrets.ANTHROPIC_API_KEY }}
  OPENAI_API_KEY: ${{ secrets.OPENAI_API_KEY }}
```

## Tips

### Cache Dependencies

Speed up workflows by caching Mix dependencies:

```yaml
- name: Cache deps
  uses: actions/cache@v4
  with:
    path: |
      deps
      _build
    key: ${{ runner.os }}-mix-${{ hashFiles('**/mix.lock') }}
    restore-keys: |
      ${{ runner.os }}-mix-
```

### Conditional Evaluation

Run evals only when relevant files change:

```yaml
on:
  push:
    paths:
      - 'lib/**'
      - 'test/evals/**'
      - 'mix.exs'
```

### Different Thresholds per Branch

Use different thresholds for main vs feature branches:

```yaml
- name: Run evaluations
  run: |
    if [ "${{ github.ref }}" = "refs/heads/main" ]; then
      mix tribunal.eval --threshold 0.9 --format github
    else
      mix tribunal.eval --threshold 0.7 --format github
    fi
```

### Post Results as PR Comment

```yaml
- name: Run evaluations
  run: mix tribunal.eval --format json --output results.json
  continue-on-error: true

- name: Post results comment
  uses: actions/github-script@v7
  if: github.event_name == 'pull_request'
  with:
    script: |
      const fs = require('fs');
      const results = JSON.parse(fs.readFileSync('results.json', 'utf8'));
      const summary = results.summary;

      const body = `## LLM Evaluation Results

      | Metric | Value |
      |--------|-------|
      | Total | ${summary.total} |
      | Passed | ${summary.passed} |
      | Failed | ${summary.failed} |
      | Pass Rate | ${Math.round(summary.pass_rate * 100)}% |
      | Duration | ${summary.duration_ms}ms |

      ${summary.failed > 0 ? '⚠️ Some evaluations failed. Check the workflow for details.' : '✅ All evaluations passed!'}`;

      github.rest.issues.createComment({
        issue_number: context.issue.number,
        owner: context.repo.owner,
        repo: context.repo.repo,
        body: body
      });
```
