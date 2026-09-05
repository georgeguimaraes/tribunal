defmodule Tribunal.ReporterTest do
  use ExUnit.Case, async: true

  alias Tribunal.Reporter.{Console, GitHub, HTML, JSON, JUnit, Text}

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
        failures: [{:faithful, "Detected unsupported claim"}],
        duration_ms: 150
      }
    ]
  }

  @sampled_results %{
    schema_version: 2,
    summary: %{
      total: 2,
      passed: 0,
      failed: 2,
      errors: 1,
      pass_rate: 0.0,
      duration_ms: 60,
      gate_status: :error
    },
    metrics: %{},
    cases: [
      %{
        input: %{"question" => "quality <case>", "tier" => "gold"},
        actual_output: "wrong <answer>",
        status: :failed,
        failures: [{:contains, "Attempt 1: missing expected text"}],
        evaluations: [
          {:contains, {:fail, %{reason: "missing first value"}}},
          {:contains, {:pass, %{reason: "matched second value"}}}
        ],
        execution_error: false,
        duration_ms: 20,
        sample: %{
          repeat: 2,
          pass_rule: :all,
          passed: 1,
          failed: 1,
          errors: 0,
          pass_rate: 0.5,
          assertions: []
        },
        attempts: [
          %{
            input: %{"question" => "quality <case>", "tier" => "gold"},
            actual_output: "first",
            status: :failed,
            failures: [{:contains, "missing expected text"}],
            evaluations: [
              {:contains, {:fail, %{reason: "missing first value"}}},
              {:contains, {:pass, %{reason: "matched second value"}}}
            ],
            execution_error: false,
            duration_ms: 10
          },
          %{
            input: %{"question" => "quality <case>", "tier" => "gold"},
            actual_output: "second",
            status: :passed,
            failures: [],
            evaluations: [
              {:contains, {:pass, %{reason: "matched first value"}}},
              {:contains, {:pass, %{reason: "matched second value"}}}
            ],
            execution_error: false,
            duration_ms: 10
          }
        ]
      },
      %{
        input: %{"question" => "timeout\n::warning::injected%", "tier" => "standard"},
        actual_output: "partial\noutput%",
        status: :failed,
        failures: [{:provider, "timeout\n::notice::fake%"}],
        evaluations: [{:contains, {:error, "timeout"}}],
        execution_error: true,
        duration_ms: 40,
        sample: %{
          repeat: 3,
          pass_rule: :any,
          passed: 2,
          failed: 1,
          errors: 1,
          pass_rate: 2 / 3,
          assertions: []
        },
        attempts: [
          %{actual_output: "attempt one", status: :passed, evaluations: []},
          %{actual_output: nil, status: :failed, evaluations: []},
          %{actual_output: "attempt three", status: :passed, evaluations: []}
        ]
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

    test "distinguishes a report-only run from a passed gate" do
      results = put_in(@sample_results, [:summary, :threshold_passed], nil)

      output = Console.format(results)

      assert output =~ "COMPLETED (no gate)"
      refute output =~ "PASSED"
    end

    test "shows FAILED for an ungated operational error" do
      results =
        @sample_results
        |> put_in([:summary, :gate_status], :error)
        |> put_in([:summary, :threshold_passed], nil)

      output = Console.format(results)

      assert output =~ "FAILED"
      refute output =~ "COMPLETED (no gate)"
    end

    test "aligns metric bars across rows" do
      results = %{
        @sample_results
        | metrics: %{
            accuracy: %{passed: 1, total: 5},
            faithfulness: %{passed: 10, total: 10}
          }
      }

      output = Console.format(results)
      lines = output |> String.split("\n") |> Enum.filter(&String.contains?(&1, "passed"))
      bar_parts = Enum.map(lines, fn line -> String.slice(line, 16..-1//1) end)
      lengths = Enum.map(bar_parts, &String.length/1)
      assert length(lengths) == 2

      assert Enum.uniq(lengths) |> length() == 1,
             "bar rows have different lengths: #{inspect(bar_parts)}"
    end

    test "renders structured sampled operational failures" do
      output = Console.format(@sampled_results)

      assert output =~ "Failed:    1"
      assert output =~ "Errors:    1"
      assert output =~ ~s("question":"timeout)
      assert output =~ "samples: 2/3 passed, 1 failed, 1 error, rule: any"
      assert output =~ "provider: timeout"
      assert output =~ ~r/Failed Cases.*quality <case>.*Errors.*timeout/s
    end
  end

  describe "Text.format/1" do
    test "shows FAILED for an ungated operational error" do
      results =
        @sample_results
        |> put_in([:summary, :gate_status], :error)
        |> put_in([:summary, :threshold_passed], nil)

      output = Text.format(results)

      assert output =~ "FAILED"
      refute output =~ "COMPLETED (no gate)"
    end

    test "aligns metric bars across rows" do
      alias Tribunal.Reporter.Text

      results = %{
        @sample_results
        | metrics: %{
            accuracy: %{passed: 1, total: 5},
            faithfulness: %{passed: 10, total: 10}
          }
      }

      output = Text.format(results)
      lines = output |> String.split("\n") |> Enum.filter(&String.contains?(&1, "passed"))
      bar_parts = Enum.map(lines, fn line -> String.slice(line, 16..-1//1) end)
      lengths = Enum.map(bar_parts, &String.length/1)
      assert length(lengths) == 2

      assert Enum.uniq(lengths) |> length() == 1,
             "bar rows have different lengths: #{inspect(bar_parts)}"
    end

    test "renders structured sampled operational failures" do
      output = Text.format(@sampled_results)

      assert output =~ "Failed:    1"
      assert output =~ "Errors:    1"
      assert output =~ ~s("question":"timeout)
      assert output =~ "samples: 2/3 passed, 1 failed, 1 error, rule: any"
      assert output =~ "provider: timeout"
      assert output =~ ~r/Failed Cases.*quality <case>.*Errors.*timeout/s
    end
  end

  describe "HTML.format/1" do
    test "shows FAILED for an ungated operational error" do
      results =
        @sample_results
        |> put_in([:summary, :gate_status], :error)
        |> put_in([:summary, :threshold_passed], nil)

      output = HTML.format(results)

      assert output =~ ">FAILED<"
      refute output =~ "COMPLETED (no gate)"
    end

    test "escapes structured sampled operational failures" do
      output = HTML.format(@sampled_results)

      assert output =~
               ~r/<div class="stat-value">1<\/div>\s+<div class="stat-label">Failed<\/div>/

      assert output =~
               ~r/<div class="stat-value">1<\/div>\s+<div class="stat-label">Errors<\/div>/

      assert output =~ ~s(<div class="failures errors">)
      assert output =~ ~s(&quot;question&quot;)
      assert output =~ "quality &lt;case&gt;"
      assert output =~ "samples: 2/3 passed, 1 failed, 1 error, rule: any"
      assert output =~ ~r/<h2>Failed Cases<\/h2>.*quality.*<h2>Errors<\/h2>.*timeout/s
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
      assert parsed["schema_version"] == 3
      assert parsed["summary"]["total"] == 10
      assert parsed["summary"]["passed"] == 8
    end

    test "includes cases" do
      output = JSON.format(@sample_results)
      {:ok, parsed} = json_decode(output)
      assert length(parsed["cases"]) == 3
    end

    test "documents the emitted failure tuple shape" do
      output = JSON.format(@sample_results)
      {:ok, parsed} = json_decode(output)

      assert %{"faithful" => "Score 0.5 below threshold 0.8"} =
               get_in(parsed, ["cases", Access.at(1), "failures", Access.at(0)])
    end

    test "preserves structured input, ordered attempts, sample stats, and duplicate evaluations" do
      output = JSON.format(@sampled_results)
      {:ok, parsed} = json_decode(output)

      assert parsed["schema_version"] == 3

      assert %{"question" => "quality <case>", "tier" => "gold"} =
               get_in(parsed, ["cases", Access.at(0), "input"])

      assert [
               %{"actual_output" => "first"},
               %{"actual_output" => "second"}
             ] =
               parsed
               |> get_in(["cases", Access.at(0), "attempts"])
               |> Enum.map(&Map.take(&1, ["actual_output"]))

      assert %{"repeat" => 2, "passed" => 1, "failed" => 1, "errors" => 0} =
               get_in(parsed, ["cases", Access.at(0), "sample"])

      assert [
               %{"type" => "contains", "result" => %{"fail" => _}},
               %{"type" => "contains", "result" => %{"pass" => _}}
             ] = get_in(parsed, ["cases", Access.at(0), "evaluations"])
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
      assert output =~ "::notice::Tribunal: 8/10 passed (80%25)"
    end

    test "includes failure reasons" do
      output = GitHub.format(@sample_results)
      assert output =~ "faithful"
    end

    test "includes actual output in annotations" do
      output = GitHub.format(@sample_results)
      assert output =~ "output: We ship worldwide to over 100 countries."
    end

    test "escapes structured sampled failures as one workflow command" do
      output = GitHub.format(@sampled_results)

      assert output =~ ~s("question":"timeout\\n::warning::injected%25")
      assert output =~ "timeout%0A::notice::fake%25"
      assert output =~ "samples: 2/3 passed, 1 failed, 1 error, rule: any"
      refute output =~ "\n::warning::injected"
      refute output =~ "\n::notice::fake"
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
      assert output =~ ~s(tests="3")
      assert output =~ ~s(failures="2")
      assert output =~ ~s(errors="0")
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

    test "counts reduced cases and separates operational errors from quality failures" do
      output = JUnit.format(@sampled_results)

      assert output =~
               ~s(<testsuites name="Tribunal" tests="2" failures="1" errors="1" time="0.06">)

      assert output =~
               ~s(<testsuite name="eval" tests="2" failures="1" errors="1" time="0.06">)

      assert output =~ "<failure message=\"Assertion failed\">"
      assert output =~ "<error message=\"Operational error\">"
      assert output =~ "samples: 2/3 passed, 1 failed, 1 error, rule: any"
      assert output =~ "quality &lt;case&gt;"
    end
  end
end
