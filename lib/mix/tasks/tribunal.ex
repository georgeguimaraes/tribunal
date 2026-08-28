defmodule Mix.Tasks.Tribunal.Eval do
  @shortdoc "Run LLM evaluations"
  @moduledoc """
  Runs LLM evaluations from dataset files.

  ## Usage

      mix tribunal.eval [options] [files...]

  ## Options

    * `--config` - Versioned YAML policy with datasets, sampling, and gates
    * `--format` - Output format: console (default), text, json, html, github, junit
    * `--output` - Write results to file instead of stdout
    * `--provider` - Module.function to call for each test case (e.g. MyApp.Agent.query)
    * `--threshold` - Minimum pass rate (0.0-1.0) required. Default: none (quality failures are report-only)
    * `--strict` - Fail on any failure, equivalent to --threshold 1.0 (for CI gates)
    * `--concurrency` - Number of test cases to run in parallel. Default: 1 (sequential)
    * `--limit` - Maximum number of test cases to evaluate
    * `--offset` - Number of test cases to skip before evaluating. Default: 0
    * `--repeat` - Number of fresh attempts per case. Default: 1
    * `--pass-rule` - Attempt rule: all, any, majority, or rate:0.8. Default: all

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

  alias Tribunal.Batch.{Policy, Report}
  alias Tribunal.Reporter.{Console, GitHub, HTML, JSON, JUnit, Text}

  @default_paths ["test/evals/**/*.json", "test/evals/**/*.yaml", "test/evals/**/*.yml"]

  @impl Mix.Task
  def run(args) do
    {opts, files, invalid} = parse_args(args)

    validate_options!(opts, invalid)

    # Start the app to load modules
    Mix.Task.run("app.start")

    settings = eval_settings(opts, files)
    files = settings.datasets

    start_time = System.monotonic_time(:millisecond)

    results =
      files
      |> Enum.flat_map(&load_dataset/1)
      |> Enum.drop(settings.offset)
      |> then(&limit_cases(&1, settings.limit))
      |> tap(&validate_group_cases!(&1, settings.group_by))
      |> run_cases(
        settings.provider,
        settings.concurrency,
        settings.repeat,
        settings.pass_rule
      )
      |> Report.build(start_time)

    {results, passed} = apply_gate(results, settings)
    formatted = format_results(results, settings.format)
    write_results(formatted, settings.output)

    unless passed, do: Mix.raise("Evaluation failed")
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
        offset: :integer,
        repeat: :integer,
        pass_rule: :string,
        config: :string,
        group_by: :string,
        group_threshold: :float
      ]
    )
  end

  defp eval_settings(opts, positional_files) do
    policy = load_policy!(opts[:config], positional_files)
    defaults = %{datasets: find_default_files(), repeat: 1, pass_rule: :all, strict: false}

    explicit =
      %{
        datasets: positional_files,
        repeat: opts[:repeat],
        pass_rule: if(opts[:pass_rule], do: parse_pass_rule(opts[:pass_rule])),
        strict: opts[:strict],
        threshold: opts[:threshold],
        group_by: opts[:group_by],
        group_threshold: opts[:group_threshold]
      }
      |> Map.reject(fn {_key, value} -> is_nil(value) end)

    resolved = resolve_policy!(policy, explicit, defaults)

    Map.merge(resolved, %{
      format: opts[:format] || "console",
      output: opts[:output],
      provider: parse_provider(opts[:provider]),
      concurrency: opts[:concurrency] || 1,
      limit: opts[:limit],
      offset: opts[:offset] || 0
    })
  end

  defp load_policy!(nil, _positional_files) do
    %{version: 1, datasets: [], sampling: %{}, gates: %{}}
  end

  defp load_policy!(path, positional_files) do
    case Policy.load(path, allow_empty_datasets: positional_files != []) do
      {:ok, policy} -> policy
      {:error, reason} -> Mix.raise("Invalid evaluation policy: #{reason}")
    end
  end

  defp resolve_policy!(policy, explicit, defaults) do
    case Policy.resolve(policy, explicit, defaults) do
      {:ok, settings} ->
        settings

      {:error, reason} ->
        if String.contains?(reason, "datasets must be a nonempty") do
          Mix.raise("No eval files found. Create datasets in test/evals/ or configure datasets")
        else
          Mix.raise("Invalid evaluation policy: #{reason}")
        end
    end
  end

  defp limit_cases(cases, nil), do: cases
  defp limit_cases(cases, limit), do: Enum.take(cases, limit)

  defp apply_gate(results, settings) do
    threshold = if settings.strict, do: 1.0, else: settings.threshold

    {results, passed} =
      Report.apply_gates(results, %{
        overall: threshold,
        groups: group_gate(settings.group_by, settings.group_threshold)
      })

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
    validate_positive!("--repeat", opts[:repeat])
    validate_offset!(opts[:offset])
    validate_format!(opts[:format])
    validate_threshold!(opts[:group_threshold])
    validate_group_options!(opts)
    validate_gate_conflict!(opts)
    if opts[:pass_rule], do: parse_pass_rule(opts[:pass_rule])
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

  defp run_cases(cases, provider, concurrency, repeat, pass_rule) do
    timeout = Application.get_env(:tribunal, :eval_timeout, 120_000)
    jobs = expand_attempts(cases, repeat)

    task_results =
      Task.Supervisor.async_stream_nolink(
        Tribunal.TaskSupervisor,
        jobs,
        fn {_case_index, _attempt_index, test_case, assertions} ->
          run_case(test_case, assertions, provider)
        end,
        max_concurrency: concurrency,
        timeout: timeout,
        on_timeout: :kill_task
      )

    jobs
    |> Enum.zip(task_results)
    |> Enum.map(fn
      {{case_index, attempt_index, _test_case, _assertions}, {:ok, result}} ->
        {case_index, attempt_index, result}

      {{case_index, attempt_index, test_case, assertions}, {:exit, reason}} ->
        result =
          Tribunal.Evaluator.error(test_case, "Evaluation task failed: #{inspect(reason)}",
            assertions: assertions,
            duration_ms: task_error_duration(reason, timeout)
          )

        {case_index, attempt_index, result}
    end)
    |> Enum.group_by(&elem(&1, 0), & &1)
    |> Enum.sort_by(&elem(&1, 0))
    |> Enum.map(fn {_case_index, attempts} ->
      attempts
      |> Enum.sort_by(&elem(&1, 1))
      |> Enum.map(&elem(&1, 2))
      |> Tribunal.Sampling.reduce(pass_rule)
    end)
  end

  defp expand_attempts(cases, repeat) do
    for {{test_case, assertions}, case_index} <- Enum.with_index(cases),
        attempt_index <- 0..(repeat - 1) do
      {case_index, attempt_index, test_case, assertions}
    end
  end

  defp task_error_duration(:timeout, timeout), do: timeout
  defp task_error_duration(_reason, _timeout), do: 0

  defp parse_pass_rule(nil), do: :all
  defp parse_pass_rule("all"), do: :all
  defp parse_pass_rule("any"), do: :any
  defp parse_pass_rule("majority"), do: :majority

  defp parse_pass_rule("rate:" <> value) do
    case Float.parse(value) do
      {rate, ""} when rate >= 0.0 and rate <= 1.0 -> {:rate, rate}
      _other -> Mix.raise("--pass-rule rate must be between 0.0 and 1.0")
    end
  end

  defp parse_pass_rule(value) do
    Mix.raise("Unknown --pass-rule #{inspect(value)}. Use all, any, majority, or rate:0.8")
  end

  defp validate_group_options!(opts) do
    if is_nil(opts[:group_by]) != is_nil(opts[:group_threshold]) do
      Mix.raise("--group-by and --group-threshold must be provided together")
    end
  end

  defp validate_gate_conflict!(opts) do
    if opts[:strict] == true and is_number(opts[:threshold]) do
      Mix.raise("--strict and --threshold cannot be used together")
    end
  end

  defp group_gate(nil, nil), do: nil
  defp group_gate(field, threshold), do: %{by: field, pass_rate: threshold}

  defp validate_group_cases!(cases, field) do
    Report.validate_group_cases!(cases, field)
  rescue
    error in ArgumentError -> Mix.raise(Exception.message(error))
  end

  defp run_case(test_case, assertions, provider) do
    case provider do
      nil ->
        Tribunal.Evaluator.evaluate(test_case, assertions)

      {mod, fun} ->
        Tribunal.Execution.run(fn -> apply(mod, fun, [test_case]) end, test_case, assertions)
    end
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
