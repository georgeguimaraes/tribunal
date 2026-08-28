defmodule Mix.Tasks.Tribunal.Redteam.Generate do
  @shortdoc "Generate red-team attack cases via configured plugins"
  @moduledoc """
  Generates a red-team dataset by invoking one or more plugins.

  Generation is separate from running. The output is a regular Tribunal
  dataset file that you execute with `mix tribunal.eval` or `tribunal_dataset/2`,
  the same as any hand-written eval suite.

  ## Usage

      mix tribunal.redteam.generate \\
        --plugins policy \\
        --purpose-file priv/purpose.txt \\
        --policy-file priv/policy.txt \\
        --count 5 \\
        --output test/evals/datasets/redteam.yaml

  ## Options

    * `--plugins` - Required. Comma-separated plugin ids (e.g., `policy`).
    * `--purpose` - Inline purpose text. Mutually exclusive with `--purpose-file`.
    * `--purpose-file` - Path to a file containing the purpose text.
    * `--policy` - Inline policy text.
    * `--policy-file` - Path to a file containing the policy text.
    * `--count` - Cases per plugin (default: 5).
    * `--output` - Path to write the dataset. Format inferred from extension
      (`.yaml`/`.yml` → YAML, `.json` → JSON). Defaults to stdout in YAML.
    * `--format` - Override format detection (`yaml` or `json`).
    * `--model` - Attacker LLM model spec, passed through to the attacker.

  ## Example

      mix tribunal.redteam.generate \\
        --plugins policy \\
        --purpose "Shopping assistant for a cosmetics retailer." \\
        --policy-file priv/policy.txt \\
        --count 5 \\
        --output test/evals/datasets/policy_redteam.yaml
  """

  use Mix.Task

  alias Tribunal.RedTeam
  alias Tribunal.RedTeam.Plugin
  alias Tribunal.RedTeam.YamlEmit

  @impl Mix.Task
  def run(args) do
    {opts, _, _} =
      OptionParser.parse(args,
        strict: [
          plugins: :string,
          purpose: :string,
          purpose_file: :string,
          policy: :string,
          policy_file: :string,
          count: :integer,
          output: :string,
          format: :string,
          model: :string
        ]
      )

    Mix.Task.run("app.start")

    plugins = parse_plugins(opts)
    purpose = read_text(opts, :purpose, :purpose_file, "purpose", required?: true)
    policy = read_text(opts, :policy, :policy_file, "policy", required?: false)

    generate_opts =
      [plugins: plugins, purpose: purpose, count: opts[:count] || 5]
      |> maybe_put(:policy, policy)
      |> maybe_put(:model, opts[:model])

    case RedTeam.generate(generate_opts) do
      {:ok, cases} -> write_output(cases, opts)
      {:error, {plugin, {:missing_options, missing}}} -> missing_options_error(plugin, missing)
      {:error, reason} -> Mix.raise("Generation failed: #{inspect(reason)}")
    end
  end

  defp missing_options_error(plugin, missing) do
    flags = Enum.map_join(missing, ", ", &"--#{&1}")
    Mix.raise("Plugin #{plugin} requires: #{flags}")
  end

  defp parse_plugins(opts) do
    case opts[:plugins] do
      nil ->
        Mix.raise("--plugins is required (e.g. --plugins policy)")

      raw ->
        raw
        |> String.split(",", trim: true)
        |> Enum.map(&resolve_plugin!/1)
    end
  end

  defp resolve_plugin!(raw_id) do
    id = String.trim(raw_id)

    case Enum.find(Plugin.all_ids(), &(Atom.to_string(&1) == id)) do
      nil -> Mix.raise("Unknown red-team plugin: #{id}")
      plugin_id -> plugin_id
    end
  end

  defp read_text(opts, inline_key, file_key, label, read_opts) do
    required? = Keyword.get(read_opts, :required?, true)

    case {opts[inline_key], opts[file_key], required?} do
      {nil, nil, true} -> Mix.raise("--#{label} or --#{label}-file is required")
      {nil, nil, false} -> nil
      {nil, path, _} -> File.read!(path)
      {text, nil, _} -> text
      {_, _, _} -> Mix.raise("--#{label} and --#{label}-file are mutually exclusive")
    end
  end

  defp maybe_put(opts, _key, nil), do: opts
  defp maybe_put(opts, key, value), do: Keyword.put(opts, key, value)

  defp write_output([], _opts) do
    Mix.shell().error("No attacks were generated; nothing written.")
  end

  defp write_output(cases, opts) do
    format = format_for(opts)
    body = encode(cases, format)

    case opts[:output] do
      nil -> Mix.shell().info(body)
      path -> File.write!(path, body)
    end
  end

  defp format_for(opts) do
    case opts[:format] do
      "json" -> :json
      "yaml" -> :yaml
      "yml" -> :yaml
      nil -> infer_format(opts[:output])
      other -> Mix.raise("Unknown --format: #{other} (expected yaml or json)")
    end
  end

  defp infer_format(nil), do: :yaml

  defp infer_format(path) do
    case Path.extname(path) do
      ".json" -> :json
      ".yaml" -> :yaml
      ".yml" -> :yaml
      ext -> Mix.raise("Cannot infer format from extension #{inspect(ext)}; pass --format")
    end
  end

  defp encode(cases, :yaml), do: YamlEmit.encode(cases)
  defp encode(cases, :json), do: JSON.encode!(prepare_json(cases)) <> "\n"

  defp prepare_json(cases) do
    Enum.map(cases, fn case_ ->
      %{
        input: case_.input,
        metadata: stringify_atoms(case_.metadata),
        expected: stringify_atoms(case_.expected)
      }
    end)
  end

  defp stringify_atoms(map) when is_map(map) do
    Map.new(map, fn {k, v} -> {to_string(k), stringify_atoms(v)} end)
  end

  defp stringify_atoms(value)
       when is_atom(value) and not is_boolean(value) and not is_nil(value) do
    Atom.to_string(value)
  end

  defp stringify_atoms(value) when is_list(value) do
    Enum.map(value, &stringify_atoms/1)
  end

  defp stringify_atoms(value), do: value
end
