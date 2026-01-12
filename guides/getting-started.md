# Getting Started

Tribunal is an LLM evaluation framework for Elixir. It provides tools for evaluating LLM outputs, detecting hallucinations, and measuring response quality.

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

## Run Evaluations

Execute evaluations against your datasets:

```bash
# Run all evals in test/evals/
mix tribunal.eval

# Run specific dataset
mix tribunal.eval test/evals/datasets/questions.json

# Output as JSON
mix tribunal.eval --format json --output results.json

# For GitHub Actions
mix tribunal.eval --format github
```

## Using with ExUnit

Integrate evaluations into your test suite:

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

- [ExUnit Integration](exunit-integration.md): Learn about all available assertion macros
- [Assertions](assertions.md): Complete reference for deterministic, LLM-as-judge, and embedding assertions
- [Datasets](datasets.md): Create and manage evaluation datasets
- [LLM-as-Judge](llm-as-judge.md): Configure and use LLM-based evaluations
