defmodule Tribunal.ExecutionTest do
  use ExUnit.Case, async: true

  alias Tribunal.{Execution, TestCase}

  @assertions [{:contains, [value: "hello"]}]

  test "evaluates binary and tagged binary provider results" do
    assert %{status: :passed, actual_output: "hello"} =
             Execution.run(fn -> "hello" end, %TestCase{input: "query"}, @assertions)

    assert %{status: :passed, actual_output: "hello"} =
             Execution.run(fn -> {:ok, "hello"} end, %TestCase{input: "query"}, @assertions)
  end

  test "uses a returned test case as the authoritative case" do
    base = %TestCase{input: "base", context: ["base context"]}

    returned = %TestCase{
      input: %{"query" => "returned"},
      evaluation_input: "returned",
      actual_output: "hello",
      context: ["returned context"]
    }

    result = Execution.run(fn -> {:ok, returned} end, base, @assertions)

    assert result.status == :passed
    assert result.input == %{"query" => "returned"}
  end

  test "rejects invalid input before invoking the provider" do
    result =
      Execution.run(
        fn -> flunk("provider should not run") end,
        %TestCase{input: %{query: "hello"}},
        @assertions
      )

    assert result.execution_error
    assert [{:input, _reason}] = result.failures
  end

  test "turns provider errors and invalid output into operational failures" do
    base = %TestCase{input: "query"}

    assert %{execution_error: true, failures: [{:provider, "unavailable"}]} =
             Execution.run(fn -> {:error, "unavailable"} end, base, @assertions)

    assert %{execution_error: true, failures: [{:provider, reason}]} =
             Execution.run(fn -> 42 end, base, @assertions)

    assert reason =~ "provider must return a binary"
  end

  test "turns exceptions and catchable exits into operational failures" do
    base = %TestCase{input: "query"}

    assert %{execution_error: true, failures: [{:provider, "boom"}]} =
             Execution.run(fn -> raise "boom" end, base, @assertions)

    assert %{execution_error: true, failures: [{:provider, reason}]} =
             Execution.run(fn -> exit(:closed) end, base, @assertions)

    assert reason == "provider exit: :closed"
  end
end
