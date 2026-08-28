# Evaluation architecture

Tribunal 2.0 has one evaluation model shared by ExUnit and `mix tribunal.eval`. The two interfaces keep their native execution behavior: ExUnit owns tests, tags, setup, timeouts, and failure presentation, while the Mix task owns batch concurrency, aggregate gates, and reports.

## The evaluation model

An evaluation moves through five separate layers:

1. A `Tribunal.TestCase` holds input, output, expected output, context, retrieval context, and metadata.
2. `Tribunal.Execution` invokes a user callback and turns its result into a populated test case or an operational error.
3. `Tribunal.Evaluator` runs assertions and produces one attempt result.
4. `Tribunal.Sampling` reduces one or more ordered attempts into one case result.
5. `Tribunal.Batch.Report` aggregates cases and applies host-configured batch gates.

Assertion metric thresholds, sampling rules, and batch gates answer different questions. A metric threshold turns one score into an assertion verdict. A sampling rule combines repeated attempts of one case. A batch gate decides whether the complete Mix run should pass.

## Test cases and structured input

`input` accepts JSON-compatible strings, numbers, booleans, lists, and string-keyed maps. Judges still need text, so `evaluation_input` can provide the exact text they should see:

```yaml
- input:
    question: Can I return an opened laptop?
    customer_tier: gold
  evaluation_input: Can I return an opened laptop?
  context:
    - Opened electronics may be returned within 14 days.
  metadata:
    category: returns
  expected:
    faithful:
      threshold: 0.85
```

When `evaluation_input` is omitted, string input is used directly and structured input is encoded as JSON. Reports retain the original structured input.

## User-owned ExUnit evaluation

`tribunal_assert` runs a zero-arity callback inside a normal user-owned test:

```elixir
test "checkout answer is stable" do
  tribunal_assert fn ->
    MyApp.Checkout.answer(%{"question" => "Can I use two coupons?"})
  end,
    input: %{"question" => "Can I use two coupons?"},
    evaluation_input: "Can I use two coupons?",
    expected_output: "Only one coupon may be applied per order.",
    context: ["One coupon may be applied per order."],
    expected: [
      faithful: [threshold: 0.85],
      relevant: [threshold: 0.8]
    ],
    repeat: 5,
    pass_rule: {:rate, 0.8}
end
```

The callback may return:

- a binary
- `{:ok, binary}`
- `{:error, reason}`
- a populated `%Tribunal.TestCase{}`
- `{:ok, %Tribunal.TestCase{}}`

A returned test case is authoritative for that attempt, which lets the application attach dynamic retrieval context or metadata. In Mix mode, gate group membership is captured from the dataset before providers run, so returned metadata cannot move a case between groups. Invalid returns, `{:error, reason}`, exceptions, throws, and catchable exits become operational attempt errors. `exit(:kill)` remains native and terminates the ExUnit test process because Tribunal does not add hidden task isolation.

`input:` and a nonempty `expected:` assertion list are required. `repeat:` defaults to `1`. `pass_rule:` defaults to `:all` and accepts `:all`, `:any`, `:majority`, or `{:rate, value}` where `value` is between `0.0` and `1.0`.

Quality failures become ExUnit assertion failures. Operational failures raise `Tribunal.ExUnit.OperationalError`, so ExUnit reports them as errors. Any operational attempt fails the reduced case even when the quality-oriented pass rule would otherwise pass.

## Dataset-generated ExUnit tests

`tribunal_dataset` creates one native ExUnit test for every dataset case:

```elixir
tribunal_dataset "test/evals/safety.yaml",
  provider: {MyApp.Chat, :reply},
  repeat: 5,
  pass_rule: :all,
  timeout: 120_000,
  defaults: [model: "anthropic:claude-sonnet-4-6"]
```

The provider is called with `test_case.input`, not the full test case. Sampling happens within each generated test. ExUnit still owns scheduling and the outer test timeout, so increase `timeout:` when repeated application and judge calls need more time.

Batch percentage gates do not apply to ExUnit. Use ordinary ExUnit behavior for hard requirements and `mix tribunal.eval` for aggregate gates.

## Mix batch evaluation

The Mix provider receives the full `Tribunal.TestCase` and follows the same callback return contract as `tribunal_assert`:

```elixir
def reply(%Tribunal.TestCase{input: input, context: context} = test_case) do
  output = MyApp.Chat.reply(input, context: context)
  %{test_case | actual_output: output}
end
```

Relevant options are:

```text
--config PATH
--repeat N
--pass-rule all|any|majority|rate:0.8
--threshold RATE
--strict
--group-by METADATA_FIELD
--group-threshold RATE
```

`--limit` and `--offset` select cases before attempt expansion. `--concurrency` bounds attempt execution. Attempt results are regrouped in dataset and attempt order before reduction.

## Version 1 policy files

`--config` loads a strict versioned YAML policy:

```yaml
version: 1
datasets:
  - test/evals/support.yaml
sampling:
  repeat: 5
  pass_rule:
    rate: 0.8
gates:
  overall:
    threshold: 0.9
  groups:
    by: error_case
    threshold: 0.8
```

Named sampling rules may also be written as `all`, `any`, or `majority`. Gate maps accept `threshold` and the equivalent `pass_rate` spelling, but not both. Unknown keys, unsupported versions, invalid values, and incomplete group gate configuration fail before evaluation.

Precedence is explicit CLI values over policy values over defaults. Positional dataset files replace the policy dataset list. Dataset paths are resolved from the current working directory.

`--strict` and an overall threshold cannot be combined. `--group-by` and `--group-threshold` must be provided together. Every selected case must have a scalar string, number, or boolean value for the configured metadata field.

## Host-owned gates

Datasets own cases, assertion configuration, and metadata. Hosts own suite policy. Overall and group gates therefore live in Mix CLI options or the policy file, not in dataset rows.

An overall gate compares the reduced case pass rate with its threshold. A group gate partitions reduced cases by one metadata field and requires every observed group to meet the same threshold. Group gates expose weak categories that an overall average could hide.

Without a quality gate, ordinary assertion failures are report-only and a successful run has `gate_status: :not_configured`. With a configured gate, `gate_status` is `:passed` or `:failed` and `threshold_passed` is the combined result. Operational errors always set `gate_status: :error` and exit nonzero. A run selecting zero cases also exits nonzero. When no quality gate is configured, `threshold_passed` remains `nil`, including operational-error runs.

## Sampling and attempt evidence

Sampling measures application nondeterminism. It is separate from infrastructure retries.

- `:all` requires every attempt to pass.
- `:any` requires at least one passing attempt.
- `:majority` requires strictly more than half to pass.
- `{:rate, value}` requires the observed attempt pass rate to meet `value`.

Operational errors override all four quality rules. Reduced cases keep ordered `attempts` as the authoritative evidence and a `sample` summary with repeat, rule, pass, failure, error, and per-assertion counts. Compatibility fields such as `actual_output`, `results`, and `evaluations` project the final attempt when a case is repeated.

## Report schema v3

JSON output uses `schema_version: 3`. It includes reduced case totals, attempt totals, assertion metrics across attempts, configured gates, ordered per-case attempt evidence, and sampling summaries. Duplicate assertions remain ordered in `evaluations`; `results` is a conservative summary by assertion type.

JUnit distinguishes quality failures from operational errors. Console, text, HTML, and GitHub output show the reduced case and sampling context.

## Deferred work

Caching, resume, classified infrastructure retries, and a public batch runner are not part of the current API. A public runner should only be added when there is a concrete programmatic consumer beyond the Mix task. Retries must stay distinct from sampling if they are added later.
