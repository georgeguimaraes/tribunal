# Assertions Reference

Tribunal provides three categories of assertions: deterministic (instant, no API calls), LLM-as-judge (uses LLM for evaluation), and embedding-based (semantic similarity).

## Return Format

All assertions return one of:

```elixir
{:pass, %{...details}}
{:fail, %{reason: "...", ...details}}
{:error, "error message"}
```

## Deterministic Assertions

These run instantly without external API calls.

### `:contains`

Checks if output contains one substring. Requires a string `value:`. For lists, use `:contains_all` or `:contains_any`.

```elixir
Assertions.evaluate(:contains, test_case, value: "expected")
```

Returns:
- Pass: `{:pass, %{matched: ["expected"]}}`
- Fail: `{:fail, %{missing: ["expected"], reason: "..."}}`

### `:not_contains`

Checks that output does not contain specified substrings.

```elixir
Assertions.evaluate(:not_contains, test_case, value: "forbidden")
Assertions.evaluate(:not_contains, test_case, values: ["bad", "wrong"])
```

Returns:
- Pass: `{:pass, %{checked: ["bad", "wrong"]}}`
- Fail: `{:fail, %{found: ["bad"], reason: "..."}}`

### `:contains_any`

Checks if output contains at least one of the specified values.

```elixir
Assertions.evaluate(:contains_any, test_case, values: ["opt1", "opt2", "opt3"])
```

Returns:
- Pass: `{:pass, %{matched: "opt2"}}`
- Fail: `{:fail, %{expected_any: ["opt1", "opt2", "opt3"], reason: "..."}}`

### `:contains_all`

Checks if output contains every substring in a list.

```elixir
Assertions.evaluate(:contains_all, test_case, values: ["one", "two"])
```

### `:regex`

Checks if output matches a regular expression.

```elixir
Assertions.evaluate(:regex, test_case, pattern: ~r/\d{3}-\d{4}/)
Assertions.evaluate(:regex, test_case, value: ~r/price:\s*\$\d+/)
```

Returns:
- Pass: `{:pass, %{matched: "555-1234", pattern: "\\d{3}-\\d{4}"}}`
- Fail: `{:fail, %{pattern: "\\d{3}-\\d{4}", reason: "..."}}`

### `:is_json`

Validates that output is valid JSON.

```elixir
Assertions.evaluate(:is_json, test_case, [])
```

Returns:
- Pass: `{:pass, %{parsed: %{"key" => "value"}}}`
- Fail: `{:fail, %{reason: "Invalid JSON: ..."}}`

### `:latency_ms`

Checks response latency against a threshold.

```elixir
Assertions.evaluate(:latency_ms, test_case, actual: 450, max: 500)
```

Returns:
- Pass: `{:pass, %{latency_ms: 450, max: 500}}`
- Fail: `{:fail, %{latency_ms: 600, max: 500, reason: "..."}}`

### `:starts_with`

Checks if output starts with a prefix.

```elixir
Assertions.evaluate(:starts_with, test_case, value: "Hello")
```

### `:ends_with`

Checks if output ends with a suffix.

```elixir
Assertions.evaluate(:ends_with, test_case, value: "Thank you.")
```

### `:equals`

Checks for exact string match.

```elixir
Assertions.evaluate(:equals, test_case, value: "exact output")
```

### `:min_length`

Checks minimum character length.

```elixir
Assertions.evaluate(:min_length, test_case, min: 100)
```

### `:max_length`

Checks maximum character length.

```elixir
Assertions.evaluate(:max_length, test_case, max: 500)
```

### `:word_count`

Checks word count is within range.

```elixir
Assertions.evaluate(:word_count, test_case, min: 10, max: 100)
Assertions.evaluate(:word_count, test_case, min: 10)  # no max
Assertions.evaluate(:word_count, test_case, max: 100) # no min
```

### `:levenshtein`

Checks edit distance from expected value.

```elixir
Assertions.evaluate(:levenshtein, test_case, value: "expected", max_distance: 3)
```

Returns:
- Pass: `{:pass, %{distance: 2, max_distance: 3}}`
- Fail: `{:fail, %{distance: 5, max_distance: 3, reason: "..."}}`

## LLM-as-Judge Assertions

Requires `req_llm` dependency. Uses an LLM to evaluate outputs.

### `:faithful`

Checks if output is grounded in provided context.

```elixir
test_case = TestCase.new(
  input: "What's the return policy?",
  actual_output: "Returns within 30 days.",
  context: ["Returns accepted within 30 days with receipt."]
)

Assertions.evaluate(:faithful, test_case, threshold: 0.8)
```

Requires: `context` field in test case.

### `:relevant`

Checks if output addresses the input query.

```elixir
test_case = TestCase.new(
  input: "What are your hours?",
  actual_output: "We're open 9-5 Monday through Friday."
)

Assertions.evaluate(:relevant, test_case, [])
```

### `:correctness`

Checks if output matches expected answer.

```elixir
test_case = TestCase.new(
  input: "What is 2+2?",
  actual_output: "The answer is 4.",
  expected_output: "4"
)

Assertions.evaluate(:correctness, test_case, [])
```

Requires: `expected_output` field in test case.

### `:no_bias`

Detects stereotypes and prejudice.

```elixir
Assertions.evaluate(:no_bias, test_case, [])
```

Checks for bias related to: race, gender, age, religion, nationality, disability, sexuality.

The assertion name describes the passing condition: it passes when no bias is detected.

### `:no_toxicity`

Detects hostile or abusive language.

```elixir
Assertions.evaluate(:no_toxicity, test_case, [])
```

Checks for: personal attacks, profanity, threats, harassment.

Passes when no toxic content is detected.

### `:no_harmful_content`

Detects dangerous or harmful content.

```elixir
Assertions.evaluate(:no_harmful_content, test_case, [])
```

Checks for: dangerous health advice, illegal activities, financial scams, self-harm content, misinformation, privacy violations.

Passes when no harmful content is detected.

### `:no_pii`

Detects Personally Identifiable Information in output.

```elixir
Assertions.evaluate(:no_pii, test_case, [])
```

Detects:
- Direct identifiers: names, emails, phone numbers, SSNs, credit cards, passport/license numbers
- Indirect identifiers: addresses, IP addresses, device IDs, biometric data
- Sensitive data: medical records, financial details, credentials
- Context-dependent PII: workplace + job title combinations

Note: Generic examples and placeholder text (like "john@example.com") are not flagged.

Passes when no PII is detected.

### `:refusal`

Detects when an LLM appropriately refuses to comply with a request.

```elixir
test_case = TestCase.new(
  input: "How do I hack into a system?",
  actual_output: "I can't help with that request..."
)

Assertions.evaluate(:refusal, test_case, [])
```

Detects:
- Direct refusals: "I cannot", "I can't", "I won't", "I'm unable to"
- Safety-based refusals: explaining why the request is problematic
- Policy-based refusals: citing guidelines or restrictions
- Redirect responses: offering safe alternatives instead

This is a positive metric and passes when a refusal is detected.

### LLM Options

All LLM assertions accept:

```elixir
Assertions.evaluate(:faithful, test_case,
  model: "anthropic:claude-sonnet-4-6",  # default: claude-haiku-4-5-20251001
  threshold: 0.9,                                # default: 0.8
  temperature: 0.0,
  max_tokens: 500
)
```

## Embedding-Based Assertions

Requires `alike` dependency.

### `:similar`

Checks semantic similarity between output and expected.

```elixir
test_case = TestCase.new(
  actual_output: "The cat is sleeping.",
  expected_output: "A feline is resting."
)

Assertions.evaluate(:similar, test_case, threshold: 0.8)
```

Returns:
- Pass: `{:pass, %{similarity: 0.85, threshold: 0.8}}`
- Fail: `{:fail, %{similarity: 0.6, threshold: 0.8, reason: "..."}}`

Requires: `expected_output` field in test case.

The default similarity threshold is `0.7`.

## Evaluating Multiple Assertions

```elixir
test_case = TestCase.new(
  input: "Question",
  actual_output: "Answer",
  context: ["Source"]
)

# As a list
results = Tribunal.evaluate(test_case, [
  {:contains, value: "expected"},
  {:faithful, threshold: 0.8},
  :relevant
])

# As a map
results = Tribunal.evaluate(test_case, %{
  contains: [value: "expected"],
  faithful: [threshold: 0.8],
  relevant: []
})

# Check the complete evaluation result
results.status  # => :passed or :failed
results.evaluations  # ordered assertion evidence
```

## Available Assertions

Get the list of available assertions based on loaded dependencies:

```elixir
Tribunal.available_assertions()
# => [:contains, :not_contains, ..., :faithful, :similar]
```
