defmodule Tribunal.EvaluatorTest do
  use ExUnit.Case, async: true

  alias Tribunal.{Evaluator, TestCase}

  test "passes when every assertion passes" do
    test_case = %TestCase{input: "hello", actual_output: "hello world"}

    result =
      Evaluator.evaluate(test_case, [
        {:contains, [value: "hello"]},
        {:not_contains, [value: "goodbye"]}
      ])

    assert result.status == :passed
    assert result.failures == []
  end

  test "fails when actual output is missing" do
    test_case = %TestCase{input: "hello"}

    result = Evaluator.evaluate(test_case, [{:contains, [value: "hello"]}])

    assert result.status == :failed
    assert result.failures == [{:evaluation, "Missing actual output"}]
  end

  test "fails when no assertions are configured" do
    test_case = %TestCase{input: "hello", actual_output: "hello world"}

    result = Evaluator.evaluate(test_case, [])

    assert result.status == :failed
    assert result.failures == [{:evaluation, "No assertions configured"}]
  end

  test "treats assertion errors as failures" do
    test_case = %TestCase{input: "hello", actual_output: "hello world"}

    result = Evaluator.evaluate(test_case, [:unknown_assertion])

    assert result.status == :failed
    assert result.failures == [{:unknown_assertion, "Unknown assertion type: unknown_assertion"}]
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

    result = Evaluator.error(test_case, "connection refused")

    assert result.status == :failed
    assert result.failures == [{:provider, "connection refused"}]
  end
end
