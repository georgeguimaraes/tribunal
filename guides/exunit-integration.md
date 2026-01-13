# ExUnit Integration

Tribunal integrates with ExUnit through the `Tribunal.EvalCase` module, providing assertion macros for LLM output evaluation.

> **Test Mode**: ExUnit assertions fail immediately on any violation. This is intentional: use Test Mode for critical checks that must pass (safety, compliance, CI gates). For threshold-based evaluation with reporting, use [Evaluation Mode](evaluation-modes.md#evaluation-mode-mix-task) instead.

## Setup

Add `use Tribunal.EvalCase` to your test module:

```elixir
defmodule MyApp.LLMTest do
  use ExUnit.Case
  use Tribunal.EvalCase

  test "response quality" do
    response = MyApp.generate("What is Elixir?")

    assert_contains response, "programming language"
    assert_min_length response, 50
  end
end
```

## Deterministic Assertions

These run instantly without external API calls.

### String Matching

```elixir
# Substring presence
assert_contains response, "expected text"
assert_contains response, ["text1", "text2"]  # all must be present
refute_contains response, "unwanted text"

# At least one must match
assert_contains_any response, ["option1", "option2", "option3"]

# All must match
assert_contains_all response, ["required1", "required2"]

# Exact match
assert_equals response, "exact expected output"

# Prefix and suffix
assert_starts_with response, "Hello"
assert_ends_with response, "Thank you."
```

### Pattern Matching

```elixir
# Regex matching
assert_regex response, ~r/\d{3}-\d{4}/

# Valid JSON
assert_json response

# Valid URL
assert_url response

# Valid email
assert_email response
```

### Length Constraints

```elixir
# Character length
assert_min_length response, 100
assert_max_length response, 500

# Word count
assert_word_count response, min: 10, max: 100

# Token limit (approximate)
assert_max_tokens response, 150
```

### Edit Distance

```elixir
# Levenshtein distance for fuzzy matching
assert_levenshtein response, "expected output", max_distance: 5
```

### Safety Checks

```elixir
# Detect refusal patterns
assert_refusal response  # passes if response is a refusal

# No PII (emails, phones, SSN, credit cards)
refute_pii response

# No toxic language
refute_toxic response
```

## LLM-as-Judge Assertions

These use an LLM to evaluate outputs. Requires `req_llm` dependency.

### Faithfulness and Relevancy

```elixir
@context ["The store is open Monday-Friday 9am-5pm."]

test "response is grounded in context" do
  response = MyApp.query("When is the store open?")

  # Output should be faithful to provided context
  assert_faithful response, context: @context

  # Output should address the query
  assert_relevant response, query: "When is the store open?"

  # No claims beyond the context
  refute_hallucination response, context: @context
end
```

### Correctness

```elixir
test "answer is correct" do
  response = MyApp.solve("What is 2 + 2?")

  assert_correctness response,
    query: "What is 2 + 2?",
    expected: "4"
end
```

### Safety Evaluations

```elixir
test "response is safe" do
  response = MyApp.chat(user_input)

  # No bias or stereotypes
  refute_bias response, query: user_input

  # No toxic language
  refute_toxicity response, query: user_input

  # No harmful advice
  refute_harmful response, query: user_input

  # No jailbreak indicators
  refute_jailbreak response, query: user_input
end
```

### Custom Rubric

```elixir
test "matches custom criteria" do
  response = MyApp.generate(prompt)

  assert_rubric response,
    query: prompt,
    rubric: """
    The response should:
    1. Be professional in tone
    2. Include specific examples
    3. Cite sources when making claims
    """
end
```

## Embedding-Based Assertions

These use semantic similarity. Requires `alike` dependency.

```elixir
test "semantically similar to expected" do
  response = MyApp.summarize(article)

  assert_similar response,
    expected: "The article discusses climate change impacts.",
    threshold: 0.8
end
```

## Dataset-Driven Testing

Generate tests automatically from JSON or YAML datasets.

### Basic Usage

```elixir
defmodule MyApp.EvalTest do
  use ExUnit.Case
  use Tribunal.EvalCase

  tribunal_eval "test/evals/datasets/questions.json"
end
```

### With Provider Function

The provider function receives each input and returns the actual output:

```elixir
tribunal_eval "test/evals/datasets/questions.json",
  provider: {MyApp.RAG, :query}
```

### With Default Options

```elixir
tribunal_eval "test/evals/datasets/questions.json",
  provider: {MyApp.RAG, :query},
  defaults: [threshold: 0.9]
```

### Dataset Format

```json
[
  {
    "input": "What is the return policy?",
    "context": "Returns accepted within 30 days with receipt.",
    "expected": {
      "contains": ["30 days"],
      "faithful": {"threshold": 0.8}
    }
  }
]
```

Each item generates a test that:
1. Calls the provider with `input`
2. Runs all assertions from `expected`
3. Fails if any assertion fails

## Options for LLM Assertions

All LLM-as-judge assertions accept these options:

```elixir
assert_faithful response,
  context: @context,
  model: "anthropic:claude-3-5-sonnet-latest",  # override default model
  threshold: 0.9,                                # pass/fail threshold
  temperature: 0.0,                              # LLM temperature
  max_tokens: 500                                # max response tokens
```

Default model: `anthropic:claude-3-5-haiku-latest`
Default threshold: `0.8`

## Test Organization

Recommended structure:

```
test/
  evals/
    datasets/
      questions.json
      safety.yaml
    my_app/
      rag_test.exs
      safety_test.exs
```

Example test file:

```elixir
# test/evals/my_app/rag_test.exs
defmodule MyApp.RAGEvalTest do
  use ExUnit.Case
  use Tribunal.EvalCase

  @moduletag :eval

  # Dataset-driven tests
  tribunal_eval "test/evals/datasets/questions.json",
    provider: {MyApp.RAG, :query}

  # Manual tests for edge cases
  describe "edge cases" do
    test "handles empty context" do
      response = MyApp.RAG.query("Unknown topic", context: [])

      assert_refusal response
    end
  end
end
```

Run just evals:

```bash
mix test --only eval
```
