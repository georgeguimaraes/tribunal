defmodule Tribunal.ReporterTest do
  use ExUnit.Case, async: true

  alias Tribunal.Reporter.{Console, GitHub, JSON, JUnit}

  @sample_results %{
    summary: %{
      total: 10,
      passed: 8,
      failed: 2,
      pass_rate: 0.8,
      duration_ms: 1500
    },
    metrics: %{
      contains: %{passed: 10, total: 10},
      faithful: %{passed: 8, total: 10}
    },
    cases: [
      %{
        input: "What's the return policy?",
        actual_output: "You can return items within 30 days with a receipt.",
        status: :passed,
        failures: [],
        duration_ms: 100
      },
      %{
        input: "Do you ship internationally?",
        actual_output: "We ship worldwide to over 100 countries.",
        status: :failed,
        failures: [
          {:faithful, "Score 0.5 below threshold 0.8"},
          {:contains, "Missing: worldwide"}
        ],
        duration_ms: 200
      },
      %{
        input: "What are the store hours?",
        actual_output: "We are open 24/7.",
        status: :failed,
        failures: [{:hallucination, "Detected unsupported claim"}],
        duration_ms: 150
      }
    ]
  }

  describe "Console.format/1" do
    test "includes header" do
      output = Console.format(@sample_results)
      assert output =~ "Tribunal LLM Evaluation"
    end

    test "includes summary stats" do
      output = Console.format(@sample_results)
      assert output =~ "Total:     10 test cases"
      assert output =~ "Passed:    8 (80%)"
      assert output =~ "Failed:    2"
    end

    test "includes metrics" do
      output = Console.format(@sample_results)
      assert output =~ "contains"
      assert output =~ "faithful"
    end

    test "includes failed cases" do
      output = Console.format(@sample_results)
      assert output =~ "Do you ship internationally?"
      assert output =~ "faithful"
    end

    test "includes actual output in failed cases" do
      output = Console.format(@sample_results)
      assert output =~ "output: We ship worldwide to over 100 countries."
    end

    test "shows FAILED status" do
      output = Console.format(@sample_results)
      assert output =~ "FAILED"
    end

    test "shows PASSED status when no failures" do
      passing_results = put_in(@sample_results, [:summary, :failed], 0)
      output = Console.format(passing_results)
      assert output =~ "PASSED"
    end
  end

  describe "JSON.format/1" do
    test "returns valid JSON" do
      output = JSON.format(@sample_results)
      assert is_binary(output)
      # Should be parseable JSON
      assert {:ok, parsed} = json_decode(output)
      assert is_map(parsed)
    end

    test "includes summary" do
      output = JSON.format(@sample_results)
      {:ok, parsed} = json_decode(output)
      assert parsed["summary"]["total"] == 10
      assert parsed["summary"]["passed"] == 8
    end

    test "includes cases" do
      output = JSON.format(@sample_results)
      {:ok, parsed} = json_decode(output)
      assert length(parsed["cases"]) == 3
    end
  end

  defp json_decode(str) do
    # Use Elixir 1.18's built-in JSON module
    {:ok, :json.decode(str)}
  rescue
    _ -> {:error, :invalid}
  end

  describe "GitHub.format/1" do
    test "outputs error annotations for failures" do
      output = GitHub.format(@sample_results)
      assert output =~ "::error::"
      assert output =~ "Do you ship internationally?"
    end

    test "outputs notice with summary" do
      output = GitHub.format(@sample_results)
      assert output =~ "::notice::Tribunal: 8/10 passed (80%)"
    end

    test "includes failure reasons" do
      output = GitHub.format(@sample_results)
      assert output =~ "faithful"
    end

    test "includes actual output in annotations" do
      output = GitHub.format(@sample_results)
      assert output =~ "output: We ship worldwide to over 100 countries."
    end
  end

  describe "JUnit.format/1" do
    test "outputs valid XML structure" do
      output = JUnit.format(@sample_results)
      assert output =~ ~s(<?xml version="1.0")
      assert output =~ "<testsuites"
      assert output =~ "<testsuite"
      assert output =~ "</testsuites>"
    end

    test "includes test count" do
      output = JUnit.format(@sample_results)
      assert output =~ ~s(tests="10")
      assert output =~ ~s(failures="2")
    end

    test "includes test cases" do
      output = JUnit.format(@sample_results)
      assert output =~ "<testcase"
      # Apostrophe is escaped in XML
      assert output =~ "What&apos;s the return policy?"
    end

    test "includes failure elements for failed tests" do
      output = JUnit.format(@sample_results)
      assert output =~ "<failure"
      assert output =~ "faithful"
    end

    test "includes actual output in failure message" do
      output = JUnit.format(@sample_results)
      assert output =~ "Output: We ship worldwide to over 100 countries."
    end

    test "escapes XML special characters" do
      results_with_special =
        put_in(@sample_results, [:cases], [
          %{
            input: "Test with <special> & \"chars\"",
            status: :passed,
            failures: [],
            duration_ms: 100
          }
        ])

      output = JUnit.format(results_with_special)
      assert output =~ "&lt;special&gt;"
      assert output =~ "&amp;"
      assert output =~ "&quot;"
    end
  end
end
