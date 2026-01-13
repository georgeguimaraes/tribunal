# Getting Started

Tribunal is an LLM evaluation framework for Elixir. It provides tools for evaluating LLM outputs, detecting hallucinations, and measuring response quality.

## Two Evaluation Modes

Tribunal offers two modes for different use cases:

- **ExUnit Mode**: Hard assertions that fail immediately. Use for safety checks, CI gates, and critical requirements.
- **Mix Task Mode**: Threshold-based evaluation with reporting. Use for benchmarking, baseline tracking, and model comparison.

See [Evaluation Modes](evaluation-modes.md) for detailed guidance on when to use each.

## Installation

Add `tribunal` to your dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:tribunal, "~> 0.1.0"}
  ]
end
```

### Optional Dependencies

For LLM-as-judge evaluations (faithfulness, relevancy, hallucination detection):

```elixir
{:req_llm, "~> 0.2"}
```

For embedding-based semantic similarity:

```elixir
{:alike, "~> 0.1"}
```

Then run:

```bash
mix deps.get
```

## Quick Example

Here's a simple evaluation using deterministic assertions:

```elixir
alias Tribunal.{TestCase, Assertions}

# Create a test case
test_case = TestCase.new(
  input: "What is the return policy?",
  actual_output: "You can return items within 30 days with a receipt.",
  context: ["Returns are accepted within 30 days of purchase with a valid receipt."]
)

# Evaluate against assertions
results = Tribunal.evaluate(test_case, [
  {:contains, value: "30 days"},
  {:contains, value: "receipt"}
])

# Check results
Assertions.all_passed?(results)
# => true
```

## Initialize Your Project

Scaffold evaluation directories with example datasets:

```bash
mix tribunal.init
```

This creates:
- `test/evals/` directory
- `test/evals/datasets/example.json`
- `test/evals/datasets/example.yaml`

## Run Evaluations (Mix Task Mode)

Execute evaluations with configurable thresholds:

```bash
# Run all evals in test/evals/ (default: exit 0, just report)
mix tribunal.eval

# Run specific dataset
mix tribunal.eval test/evals/datasets/questions.json

# Set pass threshold (fail if pass rate < 80%)
mix tribunal.eval --threshold 0.8

# Strict mode (fail on any failure)
mix tribunal.eval --strict

# Run in parallel for speed
mix tribunal.eval --concurrency 5

# Output as JSON
mix tribunal.eval --format json --output results.json

# For GitHub Actions
mix tribunal.eval --format github
```

## Using with ExUnit (Strict Mode)

ExUnit assertions fail immediately on any violation. Use for critical checks:

```elixir
defmodule MyApp.RAGTest do
  use ExUnit.Case
  use Tribunal.EvalCase

  test "response contains expected information" do
    response = MyApp.RAG.query("What's the return policy?")

    assert_contains response, "30 days"
    refute_contains response, "no returns"
  end
end
```

## Dataset-Driven Testing

Define test cases in JSON or YAML and generate tests automatically:

```elixir
defmodule MyApp.EvalTest do
  use ExUnit.Case
  use Tribunal.EvalCase

  # Generates one test per item in the dataset
  tribunal_eval "test/evals/datasets/questions.json",
    provider: {MyApp.RAG, :query}
end
```

## Next Steps

- [Evaluation Modes](evaluation-modes.md): Understand when to use ExUnit vs Mix Task
- [ExUnit Integration](exunit-integration.md): Learn about all available assertion macros
- [Assertions](assertions.md): Complete reference for deterministic, LLM-as-judge, and embedding assertions
- [Datasets](datasets.md): Create and manage evaluation datasets
- [LLM-as-Judge](llm-as-judge.md): Configure and use LLM-based evaluations
