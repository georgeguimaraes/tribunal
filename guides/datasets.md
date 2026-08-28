# Datasets

Tribunal loads evaluation cases from JSON and YAML. The same dataset can generate native ExUnit tests with `tribunal_dataset` or feed a batch run with `mix tribunal.eval`.

## Case schema

```yaml
- input:
    question: What is the return policy?
    customer_tier: gold
  evaluation_input: What is the return policy?
  context:
    - Returns are accepted within 30 days with a receipt.
  expected_output: You can return an item within 30 days with a receipt.
  metadata:
    category: returns
    critical: true
  expected:
    contains:
      - 30 days
      - receipt
    faithful:
      threshold: 0.85
```

Each case supports:

| Field | Type | Purpose |
|---|---|---|
| `input` | JSON-compatible value | Application input, required |
| `evaluation_input` | string | Optional textual input shown to judges |
| `actual_output` | string | Precomputed output, optional when a provider is used |
| `expected_output` | string | Golden answer for correctness or similarity |
| `context` | string or list | Ground-truth context |
| `retrieval_context` | string or list | Context retrieved by the application |
| `metadata` | object | Host data used in reports and group gates |
| `expected` | object | Assertions and their options |

`input` may be a string, number, boolean, list, or string-keyed map as long as it is JSON-compatible. An explicit `evaluation_input` is useful when judges should see a human question rather than the full structured input. Without one, Tribunal uses string input directly or JSON-encodes structured input.

Assertion metric thresholds belong beside the assertion they control:

```yaml
expected:
  faithful:
    threshold: 0.9
  similar:
    threshold: 0.75
```

Batch pass-rate thresholds do not belong in a dataset. Configure them in the host command or a batch policy file.

## Assertion definitions

The `expected` map supports shorthand values and option maps:

```yaml
expected:
  contains: expected text
  contains_any:
    - first answer
    - second answer
  max_tokens:
    max: 100
  relevant: {}
  faithful:
    threshold: 0.9
    model: anthropic:claude-sonnet-4-6
```

See the [assertions guide](assertions.md) for assertion-specific fields.

## Loading datasets

```elixir
alias Tribunal.Dataset

{:ok, cases} = Dataset.load("test/evals/questions.yaml")
{:ok, items} = Dataset.load_with_assertions("test/evals/questions.yaml")

cases = Dataset.load!("test/evals/questions.yaml")
items = Dataset.load_with_assertions!("test/evals/questions.yaml")
```

`load_with_assertions/1` returns `{test_case, assertions}` tuples.

## ExUnit-generated tests

```elixir
defmodule MyApp.EvalTest do
  use ExUnit.Case
  use Tribunal.ExUnit

  tribunal_dataset "test/evals/questions.yaml",
    provider: {MyApp.RAG, :query},
    repeat: 5,
    pass_rule: {:rate, 0.8},
    timeout: 120_000,
    defaults: [model: "anthropic:claude-sonnet-4-6"]
end
```

One dataset case becomes one native ExUnit test. The provider receives `test_case.input` and may return a binary, `{:ok, binary}`, `{:error, reason}`, a populated `Tribunal.TestCase`, or `{:ok, test_case}`. For a returned test case, the returned value is authoritative for that attempt.

`repeat:` defaults to `1`. `pass_rule:` defaults to `:all` and also accepts `:any`, `:majority`, and `{:rate, value}`. Any operational attempt errors the generated test regardless of the sampling rule.

## Mix batch runs

```bash
mix tribunal.eval test/evals/questions.yaml \
  --provider MyApp.RAG.query \
  --repeat 5 \
  --pass-rule rate:0.8 \
  --threshold 0.9
```

The Mix provider receives the full `Tribunal.TestCase`. Positional files replace datasets configured by `--config`. The Mix task owns overall and metadata-group gates.

## Group metadata

Group gates require every selected case to have the configured metadata field with a scalar string, number, or boolean value:

```yaml
- input: Can I return an opened laptop?
  metadata:
    category: electronics
  expected:
    refusal: {}
```

```bash
mix tribunal.eval --group-by category --group-threshold 0.8
```

Every observed category must meet the threshold. Missing values, compound values, or conflicting atom and string metadata keys fail configuration rather than silently dropping cases.

## Project layout

```text
test/
  evals/
    questions.yaml
    safety.yaml
    my_app_eval_test.exs
```

`mix tribunal.init` creates example JSON and YAML datasets under `test/evals/datasets/`.
