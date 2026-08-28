defmodule Tribunal.EvaluatorTest do
  use ExUnit.Case, async: true

  alias Tribunal.{Evaluator, TestCase}
  alias Tribunal.Reporter.JSON, as: JSONReporter

  test "passes when every assertion passes" do
    test_case = %TestCase{input: "hello", actual_output: "hello world"}

    result =
      Evaluator.evaluate(test_case, [
        {:contains, [value: "hello"]},
        {:not_contains, [value: "goodbye"]}
      ])

    assert result.status == :passed
    assert result.failures == []
    refute result.execution_error
  end

  test "fails when actual output is missing" do
    test_case = %TestCase{input: "hello"}

    result = Evaluator.evaluate(test_case, [{:contains, [value: "hello"]}])

    assert result.status == :failed
    assert result.failures == [{:evaluation, "Missing actual output"}]
    assert [{:contains, {:error, "Missing actual output"}}] = result.evaluations
    assert result.execution_error
  end

  test "rejects unsupported structured input before assertions run" do
    test_case = %TestCase{input: %{query: "hello"}, actual_output: "hello world"}

    result = Evaluator.evaluate(test_case, [{:contains, [value: "hello"]}])

    assert result.status == :failed

    assert result.failures == [
             {:input, "input maps must use string keys and JSON-compatible values"}
           ]

    assert result.execution_error
  end

  test "fails when no assertions are configured" do
    test_case = %TestCase{input: "hello", actual_output: "hello world"}

    result = Evaluator.evaluate(test_case, [])

    assert result.status == :failed
    assert result.failures == [{:evaluation, "No assertions configured"}]
    assert result.execution_error
  end

  test "treats assertion errors as failures" do
    test_case = %TestCase{input: "hello", actual_output: "hello world"}

    result = Evaluator.evaluate(test_case, [:unknown_assertion])

    assert result.status == :failed
    assert result.failures == [{:unknown_assertion, "Unknown assertion type: unknown_assertion"}]
    assert result.execution_error
  end

  test "preserves repeated assertion results and failures" do
    test_case = %TestCase{input: "hello", actual_output: "hello world"}

    result =
      Evaluator.evaluate(test_case, [
        {:contains, [value: "hello"]},
        {:contains, [value: "goodbye"]}
      ])

    assert length(result.evaluations) == 2
    assert result.status == :failed
    assert [{:contains, _reason}] = result.failures
    assert {:fail, _} = result.results.contains
    refute result.execution_error
  end

  test "the compatibility result stays failed when a later duplicate passes" do
    test_case = %TestCase{input: "hello", actual_output: "hello world"}

    result =
      Evaluator.evaluate(test_case, [
        {:contains, [value: "goodbye"]},
        {:contains, [value: "hello"]}
      ])

    assert result.status == :failed
    assert {:fail, _} = result.results.contains
  end

  test "assertion options override defaults" do
    llm = fn model, _messages, _opts ->
      send(self(), {:model, model})
      {:ok, %{"verdict" => "yes", "reason" => "relevant", "score" => 1.0}}
    end

    test_case = %TestCase{input: "hello", actual_output: "hello world"}

    result =
      Evaluator.evaluate(
        test_case,
        [{:relevant, [model: "case-model", llm: llm]}],
        defaults: [model: "default-model"]
      )

    assert result.status == :passed
    assert_received {:model, "case-model"}
  end

  test "represents provider failures as failed cases" do
    test_case = %TestCase{input: "hello"}

    result =
      Evaluator.error(test_case, "connection refused",
        assertions: [{:contains, [value: "hello"]}]
      )

    assert result.status == :failed
    assert result.failures == [{:provider, "connection refused"}]
    assert [{:contains, {:error, "connection refused"}}] = result.evaluations
    assert result.execution_error
  end

  test "preserves an explicit execution duration for task failures" do
    test_case = %TestCase{input: "hello"}

    result = Evaluator.error(test_case, "timeout", duration_ms: 120_000)

    assert result.duration_ms == 120_000
  end

  test "preserves exception messages in execution failures" do
    test_case = %TestCase{input: "hello"}

    result =
      Evaluator.error(test_case, RuntimeError.exception("provider exploded"),
        assertions: [{:contains, [value: "hello"]}]
      )

    assert result.failures == [{:provider, "provider exploded"}]
    assert result.evaluations == [{:contains, {:error, "provider exploded"}}]
    assert JSONReporter.format(%{cases: [result]}) =~ "provider exploded"
  end

  test "formats non-string reason values safely" do
    test_case = %TestCase{input: "hello"}

    result = Evaluator.error(test_case, %{"reason" => %{code: 7}})

    assert result.failures == [{:provider, "%{code: 7}"}]
    assert Evaluator.failure_message(result) == "provider: %{code: 7}"
  end
end
