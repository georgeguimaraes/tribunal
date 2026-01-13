defmodule Mix.Tasks.Tribunal.Eval do
  @shortdoc "Run LLM evaluations"
  @moduledoc """
  Runs LLM evaluations from dataset files.

  ## Usage

      mix tribunal.eval [options] [files...]

  ## Options

    * `--format` - Output format: console (default), text, json, html, github, junit
    * `--output` - Write results to file instead of stdout
    * `--provider` - Module:function to call for each test case (e.g. MyApp.Agent:query)
    * `--threshold` - Minimum pass rate (0.0-1.0) required. Default: none (always exit 0)
    * `--strict` - Fail on any failure, equivalent to --threshold 1.0 (for CI gates)
    * `--concurrency` - Number of test cases to run in parallel. Default: 1 (sequential)

  ## Provider Function

  The provider function receives a `Tribunal.TestCase` struct and should return
  the LLM output as a string. The test case includes:

    * `input` - The query/prompt
    * `context` - Optional context for RAG-style queries
    * `expected_output` - Optional expected answer

  Example provider:

      def query(%Tribunal.TestCase{input: input, context: context}) do
        # Call your LLM here
        MyApp.LLM.generate(input, context: context)
      end

  ## Examples

      # Run all evals in default location
      mix tribunal.eval

      # Run specific dataset
      mix tribunal.eval test/evals/datasets/questions.json

      # Run with a provider to generate outputs
      mix tribunal.eval --provider MyApp.Agent:query

      # Output JSON for CI
      mix tribunal.eval --format json --output results.json

      # GitHub Actions annotations
      mix tribunal.eval --format github

      # Default: always exit 0 (for baseline tracking)
      mix tribunal.eval

      # Fail if pass rate < 80%
      mix tribunal.eval --threshold 0.8

      # Strict mode: fail on any failure (for CI gates)
      mix tribunal.eval --strict

      # Run 5 test cases in parallel
      mix tribunal.eval --concurrency 5
  """

  use Mix.Task

  alias Tribunal.Reporter.{Console, GitHub, HTML, JSON, JUnit, Text}

  @default_paths ["test/evals/**/*.json", "test/evals/**/*.yaml", "test/evals/**/*.yml"]

  @impl Mix.Task
  def run(args) do
    {opts, files, _} =
      OptionParser.parse(args,
        strict: [
          format: :string,
          output: :string,
          provider: :string,
          threshold: :float,
          strict: :boolean,
          concurrency: :integer
        ]
      )

    # Start the app to load modules
    Mix.Task.run("app.start")

    format = opts[:format] || "console"
    output = opts[:output]
    provider = parse_provider(opts[:provider])
    threshold = opts[:threshold]
    strict = opts[:strict] || false
    concurrency = opts[:concurrency] || 1

    files = if Enum.empty?(files), do: find_default_files(), else: files

    if Enum.empty?(files) do
      Mix.shell().info("No eval files found. Create datasets in test/evals/")
      System.halt(0)
    end

    start_time = System.monotonic_time(:millisecond)

    results =
      files
      |> Enum.flat_map(&load_and_run(&1, provider, concurrency))
      |> aggregate_results(start_time)

    # Determine pass/fail based on threshold
    passed =
      cond do
        strict -> results.summary.failed == 0
        is_number(threshold) -> results.summary.pass_rate >= threshold
        true -> true
      end

    results = put_in(results, [:summary, :threshold_passed], passed)
    results = put_in(results, [:summary, :threshold], threshold)
    results = put_in(results, [:summary, :strict], strict)

    formatted = format_results(results, format)

    if output do
      File.write!(output, formatted)
      Mix.shell().info("Results written to #{output}")
    else
      Mix.shell().info(formatted)
    end

    unless passed do
      System.halt(1)
    end
  end

  defp find_default_files do
    @default_paths
    |> Enum.flat_map(&Path.wildcard/1)
  end

  defp parse_provider(nil), do: nil

  defp parse_provider(str) do
    case String.split(str, ":") do
      [mod, fun] ->
        {Module.concat([mod]), String.to_atom(fun)}

      _ ->
        Mix.raise("Invalid provider format. Use Module:function (e.g. MyApp.RAG:query)")
    end
  end

  defp load_and_run(path, provider, concurrency) do
    Mix.shell().info("Loading #{path}...")

    cases = Tribunal.Dataset.load_with_assertions!(path)

    if concurrency > 1 do
      cases
      |> Task.async_stream(
        fn {test_case, assertions} -> run_case(test_case, assertions, provider) end,
        max_concurrency: concurrency,
        timeout: 120_000
      )
      |> Enum.map(fn {:ok, result} -> result end)
    else
      Enum.map(cases, fn {test_case, assertions} ->
        run_case(test_case, assertions, provider)
      end)
    end
  end

  defp run_case(test_case, assertions, provider) do
    start = System.monotonic_time(:millisecond)

    test_case =
      if provider do
        {mod, fun} = provider
        output = apply(mod, fun, [test_case])
        Tribunal.TestCase.with_output(test_case, output)
      else
        test_case
      end

    results =
      if test_case.actual_output do
        Tribunal.Assertions.evaluate_all(assertions, test_case)
      else
        %{}
      end

    duration = System.monotonic_time(:millisecond) - start

    failures =
      results
      |> Enum.filter(fn {_type, result} -> match?({:fail, _}, result) end)
      |> Enum.map(fn {type, {:fail, details}} -> {type, details[:reason]} end)

    %{
      input: test_case.input,
      status: if(Enum.empty?(failures), do: :passed, else: :failed),
      failures: failures,
      results: results,
      duration_ms: duration
    }
  end

  defp aggregate_results(cases, start_time) do
    duration = System.monotonic_time(:millisecond) - start_time

    passed = Enum.count(cases, &(&1.status == :passed))
    failed = Enum.count(cases, &(&1.status == :failed))
    total = length(cases)

    metrics = aggregate_metrics(cases)

    %{
      summary: %{
        total: total,
        passed: passed,
        failed: failed,
        pass_rate: if(total > 0, do: passed / total, else: 0),
        duration_ms: duration
      },
      metrics: metrics,
      cases: cases
    }
  end

  defp aggregate_metrics(cases) do
    cases
    |> Enum.flat_map(fn c ->
      Enum.map(c.results, fn {type, result} ->
        {type, match?({:pass, _}, result)}
      end)
    end)
    |> Enum.group_by(fn {type, _} -> type end, fn {_, passed} -> passed end)
    |> Enum.map(fn {type, results} ->
      {type,
       %{
         passed: Enum.count(results, & &1),
         total: length(results)
       }}
    end)
    |> Map.new()
  end

  defp format_results(results, "console"), do: Console.format(results)
  defp format_results(results, "text"), do: Text.format(results)
  defp format_results(results, "json"), do: JSON.format(results)
  defp format_results(results, "html"), do: HTML.format(results)
  defp format_results(results, "github"), do: GitHub.format(results)
  defp format_results(results, "junit"), do: JUnit.format(results)
  defp format_results(_, format), do: Mix.raise("Unknown format: #{format}")
end

defmodule Mix.Tasks.Tribunal.Init do
  @shortdoc "Initialize eval directory structure"
  @moduledoc """
  Creates the eval directory structure with example files.

  ## Usage

      mix tribunal.init
  """

  use Mix.Task

  @impl Mix.Task
  def run(_args) do
    create_dir("test/evals")
    create_dir("test/evals/datasets")

    create_file("test/evals/datasets/example.json", example_dataset_json())
    create_file("test/evals/datasets/example.yaml", example_dataset_yaml())

    Mix.shell().info("""

    ✅ Created eval structure:

        test/evals/
        └── datasets/
            ├── example.json
            └── example.yaml

    Run evals with: mix tribunal.eval
    """)
  end

  defp create_dir(path) do
    File.mkdir_p!(path)
    Mix.shell().info("Created #{path}/")
  end

  defp create_file(path, content) do
    unless File.exists?(path) do
      File.write!(path, content)
      Mix.shell().info("Created #{path}")
    end
  end

  defp example_dataset_json do
    """
    [
      {
        "input": "What is the return policy?",
        "context": "Returns are accepted within 30 days of purchase with a valid receipt. Items must be in original condition.",
        "expected": {
          "contains": ["30 days", "receipt"],
          "not_contains": ["no returns"]
        }
      },
      {
        "input": "Do you ship internationally?",
        "context": "We currently ship to the United States and Canada only.",
        "expected": {
          "contains_any": ["United States", "US", "Canada"],
          "not_contains": ["worldwide", "international"]
        }
      }
    ]
    """
  end

  defp example_dataset_yaml do
    """
    - input: What is the return policy?
      context: Returns are accepted within 30 days of purchase with a valid receipt.
      expected:
        contains:
          - 30 days
          - receipt

    - input: What are the store hours?
      context: We are open Monday through Friday, 9am to 5pm.
      expected:
        contains_any:
          - "9am"
          - "9:00"
        regex: "\\\\d+[ap]m"
    """
  end
end
