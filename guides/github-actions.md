# GitHub Actions integration

Tribunal works as an ordinary ExUnit suite for hard requirements and as a gated Mix batch for benchmark policy.

## ExUnit safety checks

Generated `tribunal_dataset` tests and user-owned `tribunal_assert` tests run through `mix test`:

Tag user-owned suites so the filtered command includes them:

```elixir
use Tribunal.ExUnit

@moduletag :eval
```

```yaml
name: LLM safety

on: [pull_request]

jobs:
  safety:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: erlef/setup-beam@v1
        with:
          elixir-version: '1.18'
          otp-version: '27'
      - run: mix deps.get
      - run: mix test --only eval
        env:
          ANTHROPIC_API_KEY: ${{ secrets.ANTHROPIC_API_KEY }}
```

ExUnit treats quality failures as assertion failures and provider, judge, or execution failures as errors.

## Gated batch evaluation

Use a checked-in policy for repeatable CI settings:

```yaml
# config/evaluation_policy.yaml
version: 1
datasets:
  - test/evals/benchmark.yaml
sampling:
  repeat: 3
  pass_rule: majority
gates:
  overall:
    threshold: 0.9
  groups:
    by: category
    threshold: 0.8
```

```yaml
name: LLM evaluation

on:
  pull_request:
  workflow_dispatch:

jobs:
  eval:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: erlef/setup-beam@v1
        with:
          elixir-version: '1.18'
          otp-version: '27'
      - run: mix deps.get
      - name: Run evaluation gate
        run: mix tribunal.eval --config config/evaluation_policy.yaml --format github
        env:
          ANTHROPIC_API_KEY: ${{ secrets.ANTHROPIC_API_KEY }}
```

Explicit CLI flags override the policy, and positional dataset files replace its dataset list:

```bash
mix tribunal.eval test/evals/pull_request.yaml \
  --config config/evaluation_policy.yaml \
  --repeat 5 \
  --pass-rule rate:0.8 \
  --threshold 0.85 \
  --group-by category \
  --group-threshold 0.75
```

Policy values override defaults. Dataset paths are resolved from the repository working directory.

## Exit behavior

Without an overall or group quality gate, configured through CLI flags or policy, ordinary quality failures are report-only. The command exits zero with `gate_status: not_configured`.

These conditions always exit nonzero:

- a configured overall or group gate fails
- a provider, assertion, judge, task, or timeout produces an operational error
- configuration is invalid
- the selected dataset contains zero cases

Operational errors set `gate_status: error`. They cannot be hidden by `any`, `majority`, or a rate sampling rule. An ungated operational error keeps `threshold_passed: null` because no quality gate was configured.

`--strict` is a zero-tolerance overall gate and cannot be combined with `--threshold`. `--group-by` and `--group-threshold` must be supplied together.

## Saving reports even when the gate fails

A failing command stops later shell commands in the same step. Generate the machine report in a step that records the exit code, upload it with `if: always()`, then preserve the original status:

```yaml
- name: Run evaluation
  id: tribunal
  continue-on-error: true
  run: >-
    mix tribunal.eval
    --config config/evaluation_policy.yaml
    --format json
    --output results.json

- name: Upload evaluation report
  if: always()
  uses: actions/upload-artifact@v4
  with:
    name: tribunal-${{ github.sha }}
    path: results.json

- name: Enforce evaluation result
  if: steps.tribunal.outcome == 'failure'
  run: exit 1
```

JSON reports use schema version 3 and include reduced case totals, attempt totals, ordered attempt evidence, sampling summaries, and overall and group gate results.

## JUnit reporting

JUnit distinguishes assertion failures from operational errors:

```yaml
- name: Produce JUnit report
  id: tribunal_junit
  continue-on-error: true
  run: mix tribunal.eval --config config/evaluation_policy.yaml --format junit --output junit.xml

- name: Publish JUnit report
  if: always()
  uses: mikepenz/action-junit-report@v4
  with:
    report_paths: junit.xml

- name: Enforce evaluation result
  if: steps.tribunal_junit.outcome == 'failure'
  run: exit 1
```

## Scheduled baselines

For broad report-only tracking, omit quality gates but keep operational failures blocking:

```yaml
name: Scheduled LLM baseline

on:
  schedule:
    - cron: '0 6 * * *'
  workflow_dispatch:

jobs:
  baseline:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: erlef/setup-beam@v1
        with:
          elixir-version: '1.18'
          otp-version: '27'
      - run: mix deps.get
      - run: >-
          mix tribunal.eval test/evals/benchmark.yaml
          --repeat 3
          --pass-rule majority
          --format json
          --output results.json
        env:
          ANTHROPIC_API_KEY: ${{ secrets.ANTHROPIC_API_KEY }}
      - uses: actions/upload-artifact@v4
        if: always()
        with:
          name: tribunal-baseline-${{ github.run_id }}
          path: results.json
          retention-days: 90
```

GitHub dependency caching is independent from Tribunal. Tribunal does not currently provide provider-output caching, assertion-result caching, resume, or infrastructure retries.
