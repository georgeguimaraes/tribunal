defmodule Tribunal.SamplingTest do
  use ExUnit.Case, async: true

  alias Tribunal.Sampling

  test "repeat one preserves the attempt and adds sample evidence" do
    attempt = attempt(:passed, 12, output: "first", extra: :preserved)

    result = Sampling.reduce([attempt], :all)

    assert Map.drop(result, [:attempts, :sample]) == attempt
    assert result.attempts == [attempt]

    assert result.sample == %{
             repeat: 1,
             pass_rule: :all,
             passed: 1,
             failed: 0,
             errors: 0,
             pass_rate: 1.0,
             assertions: [
               %{
                 index: 0,
                 type: :contains,
                 passed: 1,
                 failed: 0,
                 errors: 0,
                 pass_rate: 1.0
               }
             ]
           }
  end

  test ":all requires every attempt to pass" do
    attempts = [attempt(:passed, 10), attempt(:failed, 20)]

    result = Sampling.reduce(attempts, :all)

    assert result.status == :failed
    assert result.sample.passed == 1
    assert result.sample.failed == 1
    assert result.sample.errors == 0
    assert result.failures == [{:contains, "Attempt 2: quality failure"}]
  end

  test ":any passes when at least one attempt passes" do
    attempts = [attempt(:failed, 10), attempt(:passed, 20)]

    result = Sampling.reduce(attempts, :any)

    assert result.status == :passed
    assert result.failures == []
  end

  test ":majority requires strictly more than half" do
    tied = [attempt(:passed, 1), attempt(:failed, 1)]

    assert Sampling.reduce(tied, :majority).status == :failed

    majority = [attempt(:passed, 1), attempt(:failed, 1), attempt(:passed, 1)]

    assert Sampling.reduce(majority, :majority).status == :passed
  end

  test "rate rules pass at the exact boundary" do
    attempts = [
      attempt(:passed, 1),
      attempt(:failed, 1),
      attempt(:passed, 1),
      attempt(:passed, 1)
    ]

    assert Sampling.reduce(attempts, {:rate, 0.75}).status == :passed
    assert Sampling.reduce(attempts, {:rate, 0.76}).status == :failed
  end

  test "an operational error overrides a passing quality rule" do
    attempts = [attempt(:passed, 5), attempt(:error, 8), attempt(:passed, 13)]

    result = Sampling.reduce(attempts, :any)

    assert result.status == :failed
    assert result.execution_error

    assert result.sample == %{
             repeat: 3,
             pass_rule: :any,
             passed: 2,
             failed: 1,
             errors: 1,
             pass_rate: 2 / 3,
             assertions: [
               %{
                 index: 0,
                 type: :contains,
                 passed: 2,
                 failed: 1,
                 errors: 1,
                 pass_rate: 2 / 3
               }
             ]
           }

    assert result.sample.passed + result.sample.failed == result.sample.repeat
    assert result.sample.errors <= result.sample.failed
    assert result.failures == [{:provider, "Attempt 2: provider unavailable"}]
  end

  test "repeated results sum duration and project compatibility fields from the final attempt" do
    first = attempt(:passed, 7, output: "first", result_marker: :first)
    final = attempt(:passed, 11, output: "final", result_marker: :final)

    result = Sampling.reduce([first, final], :all)

    assert result.duration_ms == 18
    assert result.actual_output == "final"
    assert result.results == final.results
    assert result.evaluations == final.evaluations
    assert result.attempts == [first, final]
  end

  test "assertion statistics align duplicate types by declaration index" do
    first =
      attempt(:failed, 1,
        evaluations: [
          {:contains, {:pass, %{marker: :first_position}}},
          {:contains, {:fail, %{marker: :second_position}}}
        ]
      )

    second =
      attempt(:failed, 1,
        evaluations: [
          {:contains, {:error, :judge_timeout}},
          {:contains, {:pass, %{marker: :second_position}}}
        ],
        execution_error: true
      )

    result = Sampling.reduce([first, second], :all)

    assert result.sample.assertions == [
             %{
               index: 0,
               type: :contains,
               passed: 1,
               failed: 1,
               errors: 1,
               pass_rate: 0.5
             },
             %{
               index: 1,
               type: :contains,
               passed: 1,
               failed: 1,
               errors: 0,
               pass_rate: 0.5
             }
           ]
  end

  test "rejects assertion declarations that do not align by index" do
    first = attempt(:passed, 1)
    second = attempt(:passed, 1, evaluations: [{:relevant, {:pass, %{}}}])

    assert_raise ArgumentError, ~r/attempt 2 assertion declarations do not align by index/, fn ->
      Sampling.reduce([first, second], :all)
    end
  end

  test "validates attempts with actionable errors" do
    assert_raise ArgumentError, ~r/nonempty ordered list/, fn ->
      apply(Sampling, :reduce, [[], :all])
    end

    invalid = Map.delete(attempt(:passed, 1), :duration_ms)

    assert_raise ArgumentError, ~r/attempt 1 is missing required :duration_ms/, fn ->
      Sampling.reduce([invalid], :all)
    end

    inconsistent = %{attempt(:passed, 1) | execution_error: true}

    assert_raise ArgumentError, ~r/execution_error: true but status is not :failed/, fn ->
      Sampling.reduce([inconsistent], :all)
    end
  end

  test "validates pass rules with actionable errors" do
    attempts = [attempt(:passed, 1)]

    assert_raise ArgumentError, ~r/unsupported pass rule :sometimes/, fn ->
      Sampling.reduce(attempts, :sometimes)
    end

    assert_raise ArgumentError, ~r/rate pass rule must be/, fn ->
      Sampling.reduce(attempts, {:rate, 1})
    end

    assert_raise ArgumentError, ~r/value between 0.0 and 1.0/, fn ->
      Sampling.reduce(attempts, {:rate, 1.1})
    end
  end

  defp attempt(status, duration_ms, opts \\ []) do
    execution_error = Keyword.get(opts, :execution_error, status == :error)
    normalized_status = if status == :error, do: :failed, else: status

    default_evaluation =
      case status do
        :passed -> {:contains, {:pass, %{reason: "matched"}}}
        :failed -> {:contains, {:fail, %{reason: "quality failure"}}}
        :error -> {:contains, {:error, "provider unavailable"}}
      end

    failures =
      case status do
        :passed -> []
        :failed -> [{:contains, "quality failure"}]
        :error -> [{:provider, "provider unavailable"}]
      end

    result_marker = Keyword.get(opts, :result_marker, status)

    %{
      input: "input",
      actual_output: Keyword.get(opts, :output, to_string(status)),
      status: normalized_status,
      failures: failures,
      results: %{contains: result_marker},
      evaluations: Keyword.get(opts, :evaluations, [default_evaluation]),
      execution_error: execution_error,
      duration_ms: duration_ms,
      extra: Keyword.get(opts, :extra)
    }
  end
end
