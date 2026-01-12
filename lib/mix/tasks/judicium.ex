defmodule Mix.Tasks.Judicium.Eval do
  @shortdoc "Run LLM evaluations"
  @moduledoc """
  Runs LLM evaluations from dataset files.

  ## Usage

      mix judicium.eval [options] [files...]

  ## Options

    * `--format` - Output format: console (default), json, github, junit
    * `--output` - Write results to file instead of stdout
    * `--provider` - Module:function to call for each input (e.g. MyApp.RAG:query)

  ## Examples

      # Run all evals in default location
      mix judicium.eval

      # Run specific dataset
      mix judicium.eval test/evals/datasets/questions.json

      # Output JSON for CI
      mix judicium.eval --format json --output results.json

      # GitHub Actions annotations
      mix judicium.eval --format github
  """

  use Mix.Task

  @default_paths ["test/evals/**/*.json", "test/evals/**/*.yaml", "test/evals/**/*.yml"]

  @impl Mix.Task
  def run(args) do
    {opts, files, _} =
      OptionParser.parse(args,
        strict: [
          format: :string,
          output: :string,
          provider: :string
        ]
      )

    # Start the app to load modules
    Mix.Task.run("app.start")

    format = opts[:format] || "console"
    output = opts[:output]
    provider = parse_provider(opts[:provider])

    files = if Enum.empty?(files), do: find_default_files(), else: files

    if Enum.empty?(files) do
      Mix.shell().info("No eval files found. Create datasets in test/evals/")
      System.halt(0)
    end

    start_time = System.monotonic_time(:millisecond)

    results =
      files
      |> Enum.flat_map(&load_and_run(&1, provider))
      |> aggregate_results(start_time)

    formatted = format_results(results, format)

    if output do
      File.write!(output, formatted)
      Mix.shell().info("Results written to #{output}")
    else
      Mix.shell().info(formatted)
    end

    if results.summary.failed > 0 do
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

  defp load_and_run(path, provider) do
    Mix.shell().info("Loading #{path}...")

    cases = Judicium.Dataset.load_with_assertions!(path)

    Enum.map(cases, fn {test_case, assertions} ->
      run_case(test_case, assertions, provider)
    end)
  end

  defp run_case(test_case, assertions, provider) do
    start = System.monotonic_time(:millisecond)

    test_case =
      if provider do
        {mod, fun} = provider
        output = apply(mod, fun, [test_case.input])
        Judicium.TestCase.with_output(test_case, output)
      else
        test_case
      end

    results =
      if test_case.actual_output do
        Judicium.Assertions.evaluate_all(assertions, test_case)
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

  defp format_results(results, "console"), do: Judicium.Reporter.Console.format(results)
  defp format_results(results, "json"), do: Judicium.Reporter.JSON.format(results)
  defp format_results(results, "github"), do: Judicium.Reporter.GitHub.format(results)
  defp format_results(results, "junit"), do: Judicium.Reporter.JUnit.format(results)
  defp format_results(_, format), do: Mix.raise("Unknown format: #{format}")
end

defmodule Mix.Tasks.Judicium.Init do
  @shortdoc "Initialize eval directory structure"
  @moduledoc """
  Creates the eval directory structure with example files.

  ## Usage

      mix judicium.init
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

    Run evals with: mix judicium.eval
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
