defmodule Mix.Tasks.Tribunal.Eval do
  @shortdoc "Run LLM evaluations"
  @moduledoc """
  Runs LLM evaluations from dataset files.

  ## Usage

      mix tribunal.eval [options] [files...]

  ## Options

    * `--format` - Output format: console (default), text, json, html, github, junit
    * `--output` - Write results to file instead of stdout
    * `--provider` - Module.function to call for each test case (e.g. MyApp.Agent.query)
    * `--threshold` - Minimum pass rate (0.0-1.0) required. Default: none (non-empty runs exit 0 after reporting)
    * `--strict` - Fail on any failure, equivalent to --threshold 1.0 (for CI gates)
    * `--concurrency` - Number of test cases to run in parallel. Default: 1 (sequential)
    * `--limit` - Maximum number of test cases to evaluate
    * `--offset` - Number of test cases to skip before evaluating. Default: 0

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
      mix tribunal.eval --provider MyApp.Agent.query

      # Output JSON for CI
      mix tribunal.eval --format json --output results.json

      # GitHub Actions annotations
      mix tribunal.eval --format github

      # Default: complete without a quality gate (for baseline tracking)
      mix tribunal.eval

      # Fail if pass rate < 80%
      mix tribunal.eval --threshold 0.8

      # Strict mode: fail on any failure (for CI gates)
      mix tribunal.eval --strict

      # Run 5 test cases in parallel
      mix tribunal.eval --concurrency 5

      # Evaluate only the first 50 cases
      mix tribunal.eval --limit 50

      # Skip 30 cases, then evaluate the next 50
      mix tribunal.eval --offset 30 --limit 50
  """

  use Mix.Task

  alias Tribunal.Reporter.{Console, GitHub, HTML, JSON, JUnit, Text}

  @default_paths ["test/evals/**/*.json", "test/evals/**/*.yaml", "test/evals/**/*.yml"]

  @impl Mix.Task
  def run(args) do
    {opts, files, invalid} = parse_args(args)

    validate_options!(opts, invalid)

    # Start the app to load modules
    Mix.Task.run("app.start")

    settings = eval_settings(opts)
    files = resolve_files!(files)

    start_time = System.monotonic_time(:millisecond)

    results =
      files
      |> Enum.flat_map(&load_dataset/1)
      |> Enum.drop(settings.offset)
      |> then(&limit_cases(&1, settings.limit))
      |> run_cases(settings.provider, settings.concurrency)
      |> aggregate_results(start_time)

    {results, passed} = apply_gate(results, settings)
    formatted = format_results(results, settings.format)
    write_results(formatted, settings.output)

    unless passed do
      System.halt(1)
    end
  end

  defp parse_args(args) do
    OptionParser.parse(args,
      strict: [
        format: :string,
        output: :string,
        provider: :string,
        threshold: :float,
        strict: :boolean,
        concurrency: :integer,
        limit: :integer,
        offset: :integer
      ]
    )
  end

  defp eval_settings(opts) do
    %{
      format: opts[:format] || "console",
      output: opts[:output],
      provider: parse_provider(opts[:provider]),
      threshold: opts[:threshold],
      strict: opts[:strict] || false,
      concurrency: opts[:concurrency] || 1,
      limit: opts[:limit],
      offset: opts[:offset] || 0
    }
  end

  defp resolve_files!(files) do
    files = if Enum.empty?(files), do: find_default_files(), else: files

    if Enum.empty?(files) do
      Mix.raise("No eval files found. Create datasets in test/evals/")
    end

    files
  end

  defp limit_cases(cases, nil), do: cases
  defp limit_cases(cases, limit), do: Enum.take(cases, limit)

  defp apply_gate(results, settings) do
    gate_status = gate_status(results.summary, settings.strict, settings.threshold)
    passed = gate_status in [:passed, :not_configured]
    threshold_passed = if gate_status == :not_configured, do: nil, else: passed

    results = put_in(results, [:summary, :threshold_passed], threshold_passed)
    results = put_in(results, [:summary, :gate_status], gate_status)
    results = put_in(results, [:summary, :threshold], settings.threshold)
    results = put_in(results, [:summary, :strict], settings.strict)

    {results, passed}
  end

  defp write_results(formatted, nil), do: Mix.shell().info(formatted)

  defp write_results(formatted, output) do
    File.write!(output, formatted)
    Mix.shell().info("Results written to #{output}")
  end

  defp find_default_files do
    @default_paths
    |> Enum.flat_map(&Path.wildcard/1)
  end

  defp validate_options!(opts, invalid) do
    validate_known_options!(invalid)
    validate_threshold!(opts[:threshold])
    validate_positive!("--concurrency", opts[:concurrency])
    validate_positive!("--limit", opts[:limit])
    validate_offset!(opts[:offset])
    validate_format!(opts[:format])
  end

  defp validate_known_options!([]), do: :ok

  defp validate_known_options!(invalid) do
    formatted = Enum.map_join(invalid, ", ", fn {option, value} -> inspect({option, value}) end)
    Mix.raise("Invalid options: #{formatted}")
  end

  defp validate_threshold!(nil), do: :ok
  defp validate_threshold!(threshold) when threshold >= 0 and threshold <= 1, do: :ok
  defp validate_threshold!(_threshold), do: Mix.raise("--threshold must be between 0.0 and 1.0")

  defp validate_positive!(_name, nil), do: :ok
  defp validate_positive!(_name, value) when value >= 1, do: :ok
  defp validate_positive!(name, _value), do: Mix.raise("#{name} must be at least 1")

  defp validate_offset!(nil), do: :ok
  defp validate_offset!(offset) when offset >= 0, do: :ok
  defp validate_offset!(_offset), do: Mix.raise("--offset cannot be negative")

  defp validate_format!(nil), do: :ok
  defp validate_format!(format) when format in ~w(console text json html github junit), do: :ok
  defp validate_format!(format), do: Mix.raise("Unknown format: #{format}")

  defp gate_status(%{total: 0}, _strict, _threshold), do: :failed
  defp gate_status(%{failed: 0}, true, _threshold), do: :passed
  defp gate_status(_summary, true, _threshold), do: :failed

  defp gate_status(summary, _strict, threshold) when is_number(threshold) do
    if summary.pass_rate >= threshold, do: :passed, else: :failed
  end

  defp gate_status(_summary, _strict, _threshold), do: :not_configured

  defp parse_provider(nil), do: nil

  defp parse_provider(str) do
    case str |> String.split(".") |> List.pop_at(-1) do
      {fun, [_ | _] = mod_parts} ->
        {Module.concat(mod_parts), String.to_atom(fun)}

      _ ->
        Mix.raise("Invalid provider format. Use Module.function (e.g. MyApp.RAG.query)")
    end
  end

  defp load_dataset(path) do
    Mix.shell().info("Loading #{path}...")
    Tribunal.Dataset.load_with_assertions!(path)
  end

  defp run_cases(cases, provider, concurrency) do
    timeout = Application.get_env(:tribunal, :eval_timeout, 120_000)

    task_results =
      Task.Supervisor.async_stream_nolink(
        Tribunal.TaskSupervisor,
        cases,
        fn {test_case, assertions} -> run_case(test_case, assertions, provider) end,
        max_concurrency: concurrency,
        timeout: timeout,
        on_timeout: :kill_task
      )

    cases
    |> Enum.zip(task_results)
    |> Enum.map(fn
      {_case, {:ok, result}} ->
        result

      {{test_case, assertions}, {:exit, reason}} ->
        Tribunal.Evaluator.error(test_case, "Evaluation task failed: #{inspect(reason)}",
          assertions: assertions,
          duration_ms: task_error_duration(reason, timeout)
        )
    end)
  end

  defp task_error_duration(:timeout, timeout), do: timeout
  defp task_error_duration(_reason, _timeout), do: 0

  defp run_case(test_case, assertions, provider) do
    start = System.monotonic_time(:millisecond)

    case populate_output(test_case, provider) do
      {:ok, test_case} ->
        Tribunal.Evaluator.evaluate(test_case, assertions, started_at: start)

      {:error, reason} ->
        Tribunal.Evaluator.error(test_case, reason, started_at: start, assertions: assertions)
    end
  end

  defp populate_output(test_case, nil), do: {:ok, test_case}

  defp populate_output(test_case, {mod, fun}) do
    output = apply(mod, fun, [test_case])
    {:ok, Tribunal.TestCase.with_output(test_case, output)}
  rescue
    error -> {:error, Exception.message(error)}
  catch
    kind, reason -> {:error, "#{kind}: #{inspect(reason)}"}
  end

  defp aggregate_results(cases, start_time) do
    duration = System.monotonic_time(:millisecond) - start_time

    passed = Enum.count(cases, &(&1.status == :passed))
    failed = Enum.count(cases, &(&1.status == :failed))
    total = length(cases)

    metrics = aggregate_metrics(cases)

    %{
      schema_version: 2,
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
      Enum.map(Map.get(c, :evaluations, c.results), fn {type, result} ->
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
  def run(_args), do: run([], base_dir: ".")

  @doc """
  Run the init task with options.

  ## Options

    * `:base_dir` - Base directory for creating the eval structure. Defaults to current directory.
  """
  def run(_args, opts) do
    base_dir = Keyword.get(opts, :base_dir, ".")

    create_dir(Path.join(base_dir, "test/evals"))
    create_dir(Path.join(base_dir, "test/evals/datasets"))

    create_file(Path.join(base_dir, "test/evals/datasets/example.json"), example_dataset_json())
    create_file(Path.join(base_dir, "test/evals/datasets/example.yaml"), example_dataset_yaml())

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
