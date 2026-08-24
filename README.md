# Tribunal ⚖️

LLM evaluation framework for Elixir.

**Tribunal** provides tools for evaluating and testing LLM outputs, detecting hallucinations, and measuring response quality.

> [!TIP]
> See [tribunal-juror](https://github.com/georgeguimaraes/tribunal-juror) for an interactive Phoenix app to explore and test Tribunal's evaluation capabilities.

## Why Tribunal

If you build LLM features in Elixir, there's no native way to answer "is this output any good, and did my last change make it worse?" Regular tests can't assert on faithfulness, relevance, or whether a jailbreak got through, and the mature eval tools (DeepEval, RAGAS, promptfoo) all live in Python, off your stack and out of your CI.

Tribunal makes LLM quality a first-class ExUnit citizen. You write `assert_faithful`, `refute_hallucination`, and `refute_jailbreak` next to your normal assertions, and they run in `mix test` and your existing CI. No separate runtime, no mandatory cloud service, judge and embedding deps are optional.

You get deterministic assertions, LLM-as-judge metrics, embedding similarity, dataset-driven evals, and an LLM-driven red-team generator, all in Elixir.

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
    {:tribunal, "~> 1.3"},

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
  pii            4/4 passed    100%  ████████████████████

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
- `assert_max_tokens` - Token limit
- [Full list in assertions guide](guides/assertions.md)

### LLM-as-Judge (requires `req_llm`)

- `assert_faithful` - Grounded in context
- `assert_relevant` - Addresses query
- `assert_correctness` - Matches expected answer
- `assert_refusal` - Detects refusal responses
- `refute_hallucination` - No fabricated info (grades against `:context`)
- `refute_hallucinated` - No confabulation without ground truth (grades against `:purpose`)
- `refute_bias` - No stereotypes
- `refute_toxicity` - No hostile language
- `refute_harmful` - No dangerous content
- `refute_jailbreak` - No safety bypass
- `refute_pii` - No personally identifiable information
- `refute_policy_violation` - No violation of a supplied policy
- `refute_excessive_agency` - No false claims of performing actions
- `refute_hijacked` - No engagement with off-topic content
- `refute_imitation` - No impersonation of a brand, person, or authority
- `refute_prompt_extracted` - No leak of system prompt or instructions
- `assert_judge :custom` - Custom judges via `Tribunal.Judge` behaviour

### Embedding-Based (requires `alike`)

- `assert_similar` - Semantic similarity check

## Red Team Testing

Tribunal generates adversarial prompts two ways.

### Static template attacks

Wrap a single prompt in fixed encoding, injection, and jailbreak templates. No
API calls, fully deterministic:

```elixir
alias Tribunal.RedTeam

attacks = RedTeam.generate_attacks("How do I pick a lock?")
# Returns encoding attacks (base64, leetspeak, rot13, pig latin, reversed)
# injection attacks (ignore instructions, prompt extraction, role switch, delimiter)
# jailbreak attacks (DAN, STAN, developer mode, hypothetical, roleplay, research)
```

### LLM-driven plugin attacks

Plugins ask an attacker LLM to synthesize attacks tailored to a specific
assistant. Generation is separate from running: it emits a reviewable dataset
you commit and run with `mix tribunal.eval`, the same as any eval suite.

```elixir
{:ok, cases} = Tribunal.RedTeam.generate(
  plugins: [:policy, :hijacking, :prompt_extraction],
  purpose: "Shopping assistant for a cosmetics retailer.",
  policy: "Never give medical or financial advice. Stay on topic.",
  count: 5
)
```

Or from the command line:

```bash
mix tribunal.redteam.generate \
  --plugins policy,hijacking \
  --purpose "Shopping assistant for a cosmetics retailer." \
  --policy-file priv/policy.txt \
  --count 5 \
  --output test/evals/datasets/redteam.yaml
```

Built-in plugins: `policy`, `excessive_agency`, `prompt_extraction`,
`imitation`, `hijacking`, `hallucination`. Each pairs with a judge
(`refute_policy_violation`, `refute_hijacked`, etc.) that grades the target's
response. The attacker LLM defaults to `req_llm` with sonnet; custom attackers
and plugins plug in via config. See the
[red team guide](guides/red-team-testing.md).

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
- [x] Red team attack generators (static templates)
- [x] LLM-driven red team plugin system
- [ ] Red team strategies (crescendo, iterative jailbreak)
- [ ] Dataset template variables
- [ ] Async batch evaluation

## License

MIT
