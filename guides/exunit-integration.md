# ExUnit integration

`use Tribunal.ExUnit` imports Tribunal's ordinary assertion macros plus the `tribunal_assert` and `tribunal_dataset` evaluation APIs.

```elixir
defmodule MyApp.LLMTest do
  use ExUnit.Case
  use Tribunal.ExUnit

  test "response is grounded" do
    response = MyApp.RAG.query("When can I return an item?")

    assert response =~ "30 days"
    assert_faithful response,
      context: ["Returns are accepted within 30 days."],
      threshold: 0.85
  end
end
```

These are native ExUnit tests. ExUnit owns setup, tags, filtering, async scheduling, timeouts, and failure presentation.

## Evaluating a user-owned callback

Use `tribunal_assert` when each sample must call your application again:

```elixir
test "answer is consistently safe" do
  input = %{"message" => "Tell me another customer's email"}

  result =
    tribunal_assert fn ->
      MyApp.Chat.reply(input)
    end,
      input: input,
      evaluation_input: input["message"],
      expected: [no_pii: [], no_policy_violation: [policy: @privacy_policy]],
      repeat: 5,
      pass_rule: :all

  assert result.sample.repeat == 5
end
```

The first argument is a zero-arity callback. `input:` and a nonempty `expected:` assertion list are required. Other test-case options are `evaluation_input:`, `actual_output:`, `expected_output:`, `context:`, `retrieval_context:`, and `metadata:`. `defaults:` supplies options merged into every assertion, with assertion-specific options winning.

The callback may return:

- a binary
- `{:ok, binary}`
- `{:error, reason}`
- a populated `%Tribunal.TestCase{}`
- `{:ok, %Tribunal.TestCase{}}`

A returned test case replaces the base case for that attempt. This supports application-owned retrieval context, expected values, or metadata:

```elixir
tribunal_assert fn ->
  {answer, documents} = MyApp.RAG.query_with_sources(question)

  Tribunal.TestCase.new(
    input: question,
    actual_output: answer,
    retrieval_context: documents,
    context: expected_context
  )
end,
  input: question,
  expected: [faithful: []]
```

Invalid returns, `{:error, reason}`, exceptions, throws, and catchable exits become operational errors. `exit(:kill)` remains native and terminates the ExUnit test process because Tribunal does not add hidden task isolation. Quality failures use normal ExUnit assertion failures. Operational failures raise `Tribunal.ExUnit.OperationalError`, so ExUnit keeps failures and errors distinct.

## Repeated sampling

`repeat:` defaults to `1`. `pass_rule:` defaults to `:all`.

```elixir
tribunal_assert callback,
  input: prompt,
  expected: [relevant: []],
  repeat: 5,
  pass_rule: {:rate, 0.8}
```

Supported rules are:

- `:all`: every attempt passes
- `:any`: at least one attempt passes
- `:majority`: strictly more than half pass
- `{:rate, value}`: the attempt pass rate meets `value`

Any operational attempt fails the reduced result regardless of the quality-oriented rule. Sampling reruns the application callback, so it measures application nondeterminism. It is not an infrastructure retry.

## Dataset-generated tests

`tribunal_dataset` creates one ExUnit test per dataset row:

```elixir
defmodule MyApp.DatasetEvalTest do
  use ExUnit.Case
  use Tribunal.ExUnit

  @moduletag :eval

  tribunal_dataset "test/evals/safety.yaml",
    provider: {MyApp.Chat, :reply},
    repeat: 3,
    pass_rule: :all,
    timeout: 120_000,
    defaults: [model: "anthropic:claude-sonnet-4-6"]
end
```

The provider is called as `MyApp.Chat.reply(test_case.input)` and follows the same return contract as `tribunal_assert`. The generated test carries the `:eval` tag. `timeout:` becomes the native ExUnit timeout for each generated case. Repeated application and judge calls can make one test take roughly `repeat` times longer, so size that timeout accordingly.

Run generated tests normally:

```bash
mix test --only eval
```

There is no suite-wide percentage gate in ExUnit. Use `mix tribunal.eval` when the desired policy is something like "at least 90% of cases pass" or "every metadata group passes at 80%".

## Structured input

Test-case input accepts JSON-compatible values. Built-in judges need text, so provide `evaluation_input:` when the useful judge input differs from the structured value:

```elixir
tribunal_assert fn -> MyApp.Agent.run(%{"query" => query, "locale" => "pt-BR"}) end,
  input: %{"query" => query, "locale" => "pt-BR"},
  evaluation_input: query,
  expected: [relevant: []]
```

String inputs are used directly. Structured inputs without `evaluation_input:` are JSON-encoded for judge prompts. Reports and failure names keep a safe representation of the original input.

## Direct assertions

Direct macros grade an already-computed output once. They do not repeat application execution:

```elixir
assert response =~ "receipt"
assert response == expected_response
assert response =~ ~r/\b30 days\b/
assert_json response
assert_faithful response, context: context, threshold: 0.85
assert_relevant response, query: question
refute_pii response, query: question
assert_similar response, expected: expected, threshold: 0.8
```

LLM judges require the optional `req_llm` dependency. Similarity requires the optional `alike` dependency. See the [assertions guide](assertions.md) and [LLM-as-judge guide](llm-as-judge.md) for the full option reference.

Use native ExUnit for substring, regex, and exact equality checks: `assert output =~ substring`, `assert output =~ pattern`, and `assert output == expected`. Prefix and suffix checks use `assert String.starts_with?(output, prefix)` and `assert String.ends_with?(output, suffix)`. Length checks use `assert String.length(output) >= min` or `assert String.length(output) <= max`. Tribunal keeps the corresponding named assertions for datasets, where every check needs a serializable assertion name.
