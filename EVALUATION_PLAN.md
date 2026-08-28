# Tribunal evaluation plan

## Goal

Build one trustworthy evaluation model that works through both Tribunal interfaces without making either interface imitate the other.

`tribunal_eval` should continue to feel like ExUnit. `mix tribunal.eval` should continue to feel like a batch evaluation tool. They should agree on assertion results, repeated sampling, and case status because those are shared evaluation semantics.

The host application owns the definitive quality requirements. Tribunal provides measurements, reduction rules, execution controls, evidence, and reporting. Report-only evaluation remains the Mix task default.

## Current foundation

The current architecture already has the right main boundary:

```text
application provider
        |
        v
populated Tribunal.TestCase
        |
        v
Tribunal.Evaluator
        |
        +--> tribunal_eval turns the result into an ExUnit failure
        |
        +--> mix tribunal.eval aggregates results and applies batch gates
```

`Tribunal.Evaluator` owns one populated output and its assertions. It does not call the application provider, schedule work, aggregate a dataset, format reports, or interact with ExUnit.

`tribunal_eval` creates one ExUnit test per dataset row. ExUnit owns scheduling, filtering, tags, timeouts, and failure presentation. Its provider receives `test_case.input`.

`mix tribunal.eval` owns dataset execution, bounded concurrency, aggregation, reports, quality gates, and exit codes. Its provider receives the full `Tribunal.TestCase`.

This plan preserves those contracts.

## Vocabulary

The word "threshold" currently covers several different decisions. New APIs and documentation should use precise names:

1. **Metric threshold** converts one assertion score into pass or fail, such as similarity greater than or equal to `0.8`.
2. **Case policy** combines the assertion results for one output into one case status. Tribunal currently requires every configured assertion to pass.
3. **Sample policy** combines repeated attempts of the same case, such as all attempts passing or at least four of five passing.
4. **Batch gate** decides whether a dataset or metadata group is acceptable, such as an overall pass rate of `0.9` and a safety-group pass rate of `1.0`.

Metric thresholds and sample policies are shared semantics. Batch gates belong to the Mix batch interface. ExUnit should never hide a suite-wide percentage gate inside independently scheduled tests.

## Design rules

- Keep `Tribunal.Evaluator` pure and limited to one populated output.
- Keep provider execution in the adapter that owns the runtime contract.
- Share attempt reduction so ExUnit and Mix reach the same case verdict.
- Preserve every attempt and assertion result. A reduced status must not discard evidence.
- Preserve operational errors separately from quality failures through JSON, JUnit, and human reports.
- Never let `:any`, `:majority`, or a rate rule turn a provider or judge error into a passing case.
- Keep repeated sampling separate from infrastructure retries. Sampling measures nondeterminism. Retries recover from classified transient failures.
- Let the host application render prompts and execute its own application code.
- Avoid a Tribunal template language, a second test runner, hidden concurrency inside ExUnit, or a new long-running process.
- Keep all existing behavior when `repeat` is `1`.

## Stage 1: structured inputs

This stage resolves issue #32, "How to setup dataset with large prompt".

### Outcome

A dataset row can contain a string input or JSON-compatible structured input such as a map of prompt variables. The host provider receives that value and owns prompt rendering. Users do not need to copy a large application prompt into every dataset row or build a replacement Mix task.

Built-in judges still need a textual representation of the input. String inputs use the string itself. Structured inputs may provide an optional `evaluation_input` string for judges. When it is absent, Tribunal uses a JSON representation of the structured input. This fallback prevents crashes, while `evaluation_input` lets the host provide the exact user query or other meaningful text instead of asking a judge to reason about raw variables.

### Work

- Change `Tribunal.TestCase.input` from `String.t()` to `term()`, with documentation limiting serialized datasets to non-nil JSON-compatible values.
- Add an optional string `evaluation_input` field. It defaults to a string input or a JSON representation of structured input.
- Add shared input validation and run it before provider invocation in both adapters and at the public evaluator boundary. Directly constructed `%Tribunal.TestCase{}` values therefore fail closed before an unsupported term reaches application or judge code.
- Keep input formatting total even for an invalid in-memory value so error reporting itself cannot crash.
- Route built-in judge prompts through one `Tribunal.TestCase.evaluation_input/1` helper rather than interpolating `test_case.input` directly.
- Keep strings fully backward compatible.
- Update the JSON and YAML dataset loaders to retain map and list inputs rather than coercing them to strings.
- Replace the `tribunal_eval` test-name assumption that calls `String.slice/3` on every input.
- Derive an ExUnit test name in this order:
  1. `metadata.name` when present through safe string-or-atom lookup
  2. a short string input
  3. a stable, truncated inspected representation of structured input
- Keep the existing dataset index prefix so duplicate display names cannot create duplicate generated tests.
- Route every human reporter through one structured-input formatter. Console, Text, GitHub, JUnit, and HTML must not interpolate or escape arbitrary input values directly.
- Bump the batch JSON schema version because `input` changes from string-only to string-or-structured data.
- Keep provider contracts unchanged:
  - ExUnit provider receives the structured `test_case.input` value.
  - Mix provider receives the full `Tribunal.TestCase`.
- Document the recommended provider shape:

For ExUnit's input-only provider contract:

```elixir
def evaluate_case(vars) do
  vars
  |> MyApp.Prompts.render_support_prompt()
  |> MyApp.SupportAgent.run()
end
```

For the Mix task's full-case provider contract:

```elixir
def evaluate_case(%Tribunal.TestCase{input: vars}) do
  evaluate_case(vars)
end
```

### Deliberate exclusions

- No Mustache, EEx, Liquid, or YAML variable substitution inside Tribunal.
- No template fields in the dataset schema.
- No application-specific prompt registry.

### Verification

- A string-input dataset behaves exactly as it does today through ExUnit and Mix.
- A map-input dataset reaches both provider contracts unchanged.
- Built-in judges receive `evaluation_input` or the documented JSON fallback without raising `String.Chars` errors.
- `tribunal_eval` creates readable test names for strings, maps, and lists.
- Duplicate names remain distinct because their dataset indexes are retained.
- Human reporters render maps and lists without crashing or creating invalid JUnit or HTML.
- Missing inputs fail at the dataset boundary. Unsupported in-memory values fail before provider invocation with a useful reason.
- The JSON schema documents both string and structured inputs.

## Stage 2: attempt-aware shared results

This stage creates the result model needed by repeated sampling before adding new execution behavior. It can proceed independently from structured-input work.

### Outcome

Tribunal can represent one or more complete evaluation attempts without flattening them into one output or losing duplicate assertions.

### Result shape

One attempt remains the result of evaluating one populated output. A reduced case result adds attempt information while preserving the current top-level status for compatibility:

```elixir
%{
  status: :passed,
  execution_error: false,
  input: input,
  actual_output: actual_output,
  metadata: metadata,
  provenance: provenance,
  attempts: [attempt_result],
  sample: %{
    repeat: 1,
    pass_rule: :all,
    passed: 1,
    failed: 0,
    errors: 0,
    pass_rate: 1.0
  }
}
```

The first implementation can keep maps and strengthen their typespecs. A public struct should only be introduced if it clearly improves validation without causing an unnecessary compatibility migration.

Each attempt should retain:

- actual output
- status
- execution-error state and reason
- assertion evaluations in declaration order
- assertion scores, thresholds, reasons, and details when available
- provider duration and assertion or judge duration when measurable

Repeated assertions of the same type are aligned by declaration position, not only by assertion name.

### Work

- Add a pure `Tribunal.Sampling.reduce/2` boundary that receives complete evaluator results.
- Define and validate the shared sample-rule representation.
- Make an operational error override all quality-oriented sample rules.
- Preserve input, metadata, dataset position, and source file when the adapter knows them. Keep provenance internal until the attempt-aware JSON schema ships.
- For `repeat: 1`, preserve the exact current top-level `input`, `actual_output`, `status`, `failures`, `results`, `evaluations`, `execution_error`, and `duration_ms` keys and values.
- For `repeat > 1`, make `status`, `failures`, and `execution_error` reduced case values. Keep `actual_output`, `results`, and `evaluations` as explicitly documented final-attempt compatibility projections while `attempts` remains the authoritative complete evidence. `duration_ms` is the total duration across attempts.
- Add attempt-aware failure formatting for ExUnit and reporters.
- Keep top-level status as `:failed` for both quality failures and operational errors. `execution_error: true` distinguishes the latter so current aggregation does not silently miss them.
- Define sampling counters so `passed + failed == repeat`, `errors <= failed`, and `failed` includes errored attempts.
- Start with truthful coarse error categories: provider exception, attempt timeout or task exit, missing output, missing assertions, assertion error, and invalid assertion result. Mix cannot distinguish a provider timeout from a judge timeout with its current task boundary, so it reports an attempt timeout unless later instrumentation can prove the phase.

### Initial sample rules

- `:all` passes when every attempt passes.
- `:any` passes when at least one attempt passes.
- `:majority` passes when more than half of the attempts pass.
- `{:rate, value}` passes when the attempt pass rate is greater than or equal to `value`.

`repeat` defaults to `1`. When a caller chooses `repeat > 1` without a rule, the rule defaults to `:all` and must be shown in output and serialized results.

### Verification

- Every rule is tested at its exact boundary.
- Any execution error produces a failed case with `execution_error: true` regardless of the quality rule.
- Sampling counts satisfy their documented invariants for quality failures and errors.
- Duplicate assertions retain independent attempt counts.
- Attempt order is stable even when Mix executes attempts concurrently.
- `repeat: 1` produces the same case status and failure text as the current evaluator wherever possible.

## Stage 3: repeated sampling in ExUnit and Mix

This stage resolves the nondeterministic-test portion of issue #35, "More options for thresholds".

### ExUnit behavior

`tribunal_eval` accepts `repeat:` and `pass_rule:`:

```elixir
tribunal_eval "test/evals/safety.yaml",
  provider: {MyApp.Agent, :run},
  repeat: 5,
  pass_rule: :all
```

One dataset row remains one ExUnit test. That test invokes the provider repeatedly, evaluates each populated output, calls the shared reducer, and flunks once with the attempt evidence.

Provider exceptions and caught exits become errored attempts so later attempts can still run. After reduction, a quality failure uses `flunk/1`, while an operationally errored case raises a dedicated Tribunal exception so ExUnit reports an error rather than an assertion failure. This intentionally preserves the distinction ExUnit has today.

Provider calls are sequential within one generated test initially. ExUnit already provides concurrency across tests, and a second scheduler inside a test would make timeouts and load difficult to understand.

The macro accepts a `timeout:` option and applies it as the generated ExUnit test timeout. The documentation must make the multiplier visible because five attempts plus five judge calls can make one test roughly five times slower.

The outer ExUnit timeout remains authoritative. If it kills the generated test, Tribunal cannot preserve partial attempt evidence without adding hidden task machinery. The failure message should tell users to increase `timeout:` when repeated evaluation is expected to run longer.

Ordinary assertion macros continue to grade one already-computed output. They do not receive `repeat:`. A later `assert_consistently` convenience macro can wrap a generator only after repeated dataset evaluation proves the shared API.

### Mix behavior

The Mix task accepts:

```text
--repeat N
--pass-rule all|any|majority|rate:P
```

Mix expands work into indexed `{case, attempt}` jobs, executes them under one bounded concurrency limit, then regroups attempts in dataset order before reduction.

Each attempt gets its own attempt timeout and isolation covering provider execution plus assertions and judges. Repeats must not be implemented as a loop inside the current timed case task because that would silently change a per-attempt timeout into a whole-sample timeout. Nested task streams are also excluded because they multiply concurrency.

Human reports show the planned work clearly:

```text
50 cases x 5 attempts = 250 attempt evaluations
target provider calls: 250
sample policy: all
```

Precomputed-output datasets may have zero target-provider calls while still repeating judge assertions. Machine-oriented output stays parseable and receives these counts as structured fields rather than extra planning lines on stdout.

### Verification

- ExUnit and Mix reduce the same synthetic attempt sequence to the same status.
- ExUnit reports quality failures as failures and provider errors as errors.
- The macro timeout is applied to each generated ExUnit test.
- Mix never exceeds the configured global concurrency.
- One timed-out attempt does not destroy the remaining dataset results.
- Results remain in stable case and attempt order after concurrent execution.
- Attempt-evaluation counts match `selected cases x repeat` exactly.
- Target-provider call counts are accurate for live providers and precomputed outputs.
- `--limit` and `--offset` apply to cases before repeat expansion.

## Stage 4: complete attempt reporting

Repeated sampling is not complete until every report format represents it honestly.

### Outcome

Users can distinguish a consistently failing case, a flaky quality failure, and an operational failure without rerunning the evaluation.

### Work

- Bump the batch JSON schema version.
- Include sample configuration, attempt summaries, complete attempt results, provenance, and error classification in JSON. This is the first release that exposes provenance publicly.
- Add per-assertion attempt counts and pass rates.
- Show concise attempt summaries in Console, Text, GitHub, and HTML output.
- Represent quality failures as JUnit failures and operational errors as JUnit errors.
- Keep full evidence in JSON even when human formats summarize it.

### Example human output

```text
Failed cases
  return policy for electronics
    faithful: 3/5 passed, flaky quality failure

  opened software return
    relevant: 0/5 passed, consistent quality failure

  account cancellation
    provider: 1 timeout, operational error
```

### Verification

- JSON round-trips every attempt and duplicate assertion.
- All reporters agree on totals, pass rates, errors, and the applied sample rule.
- Existing schema-version consumers get a documented migration note.

Stages 2 through 4 form one user-visible feature. They can be separate implementation pull requests, but repeated sampling should not be released with console-only evidence or an incomplete JSON contract.

## Stage 5: batch and group gates

This stage resolves the group-threshold portion of issue #35, "More options for thresholds".

### Outcome

The Mix task can reject a run when one important category regresses even if the overall dataset pass rate remains acceptable.

### Global gate

Keep the current `--threshold` behavior for compatibility. Document it as the batch pass-rate threshold. A future clearer alias such as `--pass-rate-threshold` can be added without removing the existing flag.

Operational errors always fail the run. A quality gate never hides them.

### Group gate

Start with one simple, useful form:

```text
mix tribunal.eval --threshold 0.90 --group-by error_case --group-threshold 0.80
mix tribunal.eval --group-by plugin --group-threshold 1.0
```

The group key is read from `TestCase.metadata` using safe string-or-atom lookup without creating atoms. Allowed group values are strings, numbers, and booleans. Missing keys, `nil`, maps, and lists are configuration errors that fail the run and identify every affected case. This prevents a typo or missing label from silently removing a critical case from the denominator.

Every observed valid group must meet the same configured group threshold. This directly prevents one error category or red-team plugin from failing completely while the overall run stays green. Observed-only grouping cannot prove that an expected group is absent, so an explicit required-group list can be added later if that becomes a real requirement.

Per-group custom thresholds can come later if real datasets need them. Avoid inventing a gate configuration language in the first release.

### Combined gate result

Global and group gates produce one authoritative batch decision:

- `gate_status: :error` when execution or group configuration has an operational error
- `gate_status: :failed` when cases are empty or any configured global or group quality gate fails
- `gate_status: :passed` when at least one quality gate is configured and every configured gate passes
- `gate_status: :not_configured` when no global or group quality gate is configured

`threshold_passed` remains the compatibility boolean for the combined configured quality gates. It is `true` only when all configured global and group gates pass, `false` when any configured quality gate fails, and `nil` when no quality gate is configured. Operational errors continue to be represented by `gate_status: :error` and a nonzero exit.

The versioned report adds a structured group-gate object containing the metadata key, configured threshold, invalid or missing case count, and one entry per observed group with its original scalar value, totals, pass rate, and status. Human reporters show the same group outcomes. Adding group gates therefore bumps the JSON schema and updates JSON, JUnit, Console, Text, GitHub, and HTML together.

### Confidence intervals

Wilson intervals remain valuable for datasets where a point estimate is too easy to overread. Add them after repeated sampling and group gates are stable.

The suite interval uses the number of reduced cases as `n`. Repeating each case five times does not turn a 50-case dataset into 250 independent cases. Per-case attempt intervals answer a separate flakiness question.

An eventual `--threshold-ci` option can gate on the lower Wilson bound. Bayesian modes and generalized pass@k estimators stay out of the initial roadmap until a concrete use case requires them.

### Verification

- A passing global rate with one failing group exits nonzero.
- A group failure sets combined `gate_status` and `threshold_passed` consistently in every machine format.
- Missing or invalid group metadata fails closed with a visible case count.
- Empty groups cannot pass through division behavior.
- Group counts reconcile exactly with the selected case count.
- Confidence-interval tests use published boundary examples rather than tautological implementation checks.

## Stage 6: operational controls

These features are valuable in larger Python evaluation tools, but they should follow the shared result and execution model rather than shape it prematurely.

### Usage and cost

- Keep the existing string-returning provider contracts valid.
- If richer provider results are needed, add an optional result envelope carrying output and usage rather than replacing the string contract.
- Retain judge usage from ReqLLM responses instead of discarding it before attempting normalization.
- Normalize provider-reported input tokens, output tokens, total tokens, latency, and cost.
- Keep target-application usage separate from judge usage.
- Record whether cost is provider-reported or estimated.
- Let the host configure any cost or latency gate.

### Retries

- Retry only classified transient operational failures.
- Never retry a valid low score as infrastructure recovery.
- Record every retry and the final reason.
- Keep retry count separate from sample count.

### Caching and resume

- Add caching only after the host can supply a stable application identity or version namespace.
- Provider-output cache keys must include input, provider identity, relevant provider configuration, and host-supplied application version.
- Assertion-result cache keys must also include assertion options, judge identity, and metric implementation version.
- Errors are not cached.
- Cache reads in CI are explicit unless the host configures a stable shared namespace.
- Resume skips completed indexed attempts without changing ordering or sample semantics.

### Public batch runner

Most batch orchestration currently lives privately inside the Mix task. Extract a public `Tribunal.Runner` only when there is a second real programmatic consumer. The Mix task can be refactored into smaller internal functions first. This avoids creating a public API from hypothetical requirements.

## Deferred evaluation features

- `assert_consistently` as an ExUnit convenience macro
- custom thresholds for individual metadata values
- baseline and regression-delta gates
- Bayesian confidence models
- generalized pass@k estimators
- cancellation APIs
- persistent experiment storage
- web dashboards

## Relationship to red-team evaluation

Red-team generation and evaluation remain separate. Generation produces an ordinary Tribunal dataset that can be reviewed, committed, and executed through either adapter.

Metadata provenance enables Mix group gates by plugin, strategy, severity, or policy category without creating a red-team-specific runner.

Multi-turn attacks need a separate provider or scenario contract because the current provider callbacks represent one invocation. That design should reuse the same populated case, evaluator, sampling, and reporting layers once a conversation transcript becomes the evaluated output. It should not block structured inputs, repeated sampling, or group gates.

## Proposed pull request sequence

1. **Structured inputs**: update `TestCase`, loaders, built-in judges, ExUnit names, every reporter, and the JSON input schema.
2. **Attempt result and pure reduction**: add typed provenance, the attempt-aware result shape, and `Tribunal.Sampling` with error precedence. This can proceed independently from pull request 1.
3. **ExUnit sampling**: add `repeat:` and `pass_rule:` to `tribunal_eval` with native ExUnit behavior.
4. **Mix sampling and schema**: add indexed attempt scheduling, JSON schema update, and all reporter projections.
5. **Group gates**: add metadata grouping and one shared threshold for every observed group.
6. **Confidence intervals**: add Wilson summaries and optional lower-bound gating.
7. **Operational controls**: add usage, classified retries, caching, or resume one at a time when demanded by real workloads.

Each pull request should preserve default behavior, update the relevant guides, and include tests for the branches that could produce a false green result.

## Completion criteria

The roadmap is complete when:

- structured inputs work through both existing provider contracts
- ExUnit and Mix produce the same reduced case verdict from the same attempts
- all operational errors remain distinguishable from quality failures
- every reporter accurately represents repeated attempts
- overall and metadata-group gates work without hidden suite logic in ExUnit
- the host application supplies every definitive acceptance value
- no new Tribunal template language or duplicate execution framework has been introduced
