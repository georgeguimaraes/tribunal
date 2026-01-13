# Tribunal

LLM evaluation framework for Elixir.

**Tribunal** provides tools for evaluating LLM outputs, detecting hallucinations, and measuring response quality.

> [!TIP]
> See [tribunal-juror](https://github.com/georgeguimaraes/tribunal-juror) for an interactive Phoenix app to explore and test Tribunal's evaluation capabilities.

## Test Mode vs Evaluation Mode

Tribunal offers two modes for different use cases:

| Mode | Interface | Use Case | Failure Behavior |
|------|-----------|----------|------------------|
| **Test** | ExUnit | CI gates, safety checks | Fails immediately on any failure |
| **Evaluation** | Mix Task | Benchmarking, baseline tracking | Configurable thresholds |

**Test Mode** is for "this must work" cases: safety checks, refusal detection, critical RAG accuracy. Tests fail fast on any violation.

**Evaluation Mode** is for "track how well we're doing": run hundreds of evals, compare models, monitor regression over time. Set thresholds like "pass if 80% succeed."

## Installation

```elixir
def deps do
  [
    {:tribunal, "~> 0.1.0"},

    # Optional: for LLM-as-judge evaluations
    {:req_llm, "~> 1.2"},

    # Optional: for embedding-based similarity
    {:alike, "~> 0.1"}
  ]
end
```

## Quick Start

### ExUnit Integration

```elixir
defmodule MyApp.RAGTest do
  use ExUnit.Case
  use Tribunal.EvalCase

  @context ["Returns are accepted within 30 days with receipt."]

  test "response is faithful to context" do
    response = MyApp.RAG.query("What's the return policy?")

    assert_contains response, "30 days"
    assert_faithful response, context: @context
    refute_hallucination response, context: @context
  end
end
```

### Dataset-Driven Evaluations

```elixir
# test/evals/rag_test.exs
defmodule MyApp.RAGEvalTest do
  use ExUnit.Case
  use Tribunal.EvalCase

  tribunal_eval "test/evals/datasets/questions.json",
    provider: {MyApp.RAG, :query}
end
```

### Evaluation Mode (Mix Task)

```bash
# Initialize evaluation structure
mix tribunal.init

# Run evaluations (default: always exit 0, just report)
mix tribunal.eval

# Set pass threshold (fail if pass rate < 80%)
mix tribunal.eval --threshold 0.8

# Strict mode (fail on any failure)
mix tribunal.eval --strict

# Run in parallel for speed
mix tribunal.eval --concurrency 5

# Output formats
mix tribunal.eval --format json --output results.json
mix tribunal.eval --format github  # GitHub Actions annotations
```

```
Tribunal LLM Evaluation
═══════════════════════════════════════════════════════════════

Summary
───────────────────────────────────────────────────────────────
  Total:     12 test cases
  Passed:    10 (83%)
  Failed:    2
  Duration:  1.4s

Results by Metric
───────────────────────────────────────────────────────────────
  faithful       8/8 passed    100%  ████████████████████
  relevant       6/8 passed    75%   ███████████████░░░░░
  contains       10/10 passed  100%  ████████████████████
  no_pii         4/4 passed    100%  ████████████████████

Failed Cases
───────────────────────────────────────────────────────────────
  1. "What is the return policy for electronics?"
     ├─ relevant: Response discusses refunds but doesn't address return policy

  2. "Can I return opened software?"
     ├─ relevant: Response is generic, doesn't mention software-specific policy

───────────────────────────────────────────────────────────────
✅ PASSED (threshold: 80%)
```

## Assertion Types

### Deterministic (instant, no API calls)

- `assert_contains` / `refute_contains` - Substring matching
- `assert_regex` - Pattern matching
- `assert_json` - Valid JSON validation
- `assert_refusal` - Refusal pattern detection
- `assert_max_tokens` - Token limit
- `refute_pii` - No PII detection
- `refute_toxic` - No toxic patterns
- [Full list in assertions guide](guides/assertions.md)

### LLM-as-Judge (requires `req_llm`)

- `assert_faithful` - Grounded in context
- `assert_relevant` - Addresses query
- `refute_hallucination` - No fabricated info
- `refute_bias` - No stereotypes
- `refute_toxicity` - No hostile language
- `refute_harmful` - No dangerous content
- `refute_jailbreak` - No safety bypass

### Embedding-Based (requires `alike`)

- `assert_similar` - Semantic similarity check

## Red Team Testing

Generate adversarial prompts to test LLM safety:

```elixir
alias Tribunal.RedTeam

attacks = RedTeam.generate_attacks("How do I pick a lock?")
# Returns encoding attacks (base64, leetspeak, rot13)
# injection attacks (ignore instructions, delimiter injection)
# jailbreak attacks (DAN, STAN, developer mode)
```

## Guides

- [Getting Started](guides/getting-started.md)
- [Test vs Evaluation Mode](guides/evaluation-modes.md)
- [ExUnit Integration](guides/exunit-integration.md)
- [Assertions Reference](guides/assertions.md)
- [LLM-as-Judge](guides/llm-as-judge.md)
- [Datasets](guides/datasets.md)
- [Red Team Testing](guides/red-team-testing.md)
- [Reporters](guides/reporters.md)
- [GitHub Actions](guides/github-actions.md)

## Roadmap

- [x] Core evaluation pipeline
- [x] Faithfulness metric (RAGAS-style)
- [x] Hallucination detection
- [x] LLM-as-judge with configurable models
- [x] ExUnit integration for test assertions
- [x] Red team attack generators
- [ ] Async batch evaluation

## License

MIT
