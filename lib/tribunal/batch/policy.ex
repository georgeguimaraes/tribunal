defmodule Tribunal.Batch.Policy do
  @moduledoc """
  Loads and resolves versioned batch evaluation policy files.

  Policy files use string keys at the YAML boundary and are normalized into a
  fixed atom-keyed shape. Dataset paths are expanded relative to the current
  working directory, not relative to the policy file.
  """

  @version 1
  @top_level_keys ~w(version datasets sampling gates)
  @sampling_keys ~w(repeat pass_rule)
  @rate_keys ~w(rate)
  @gate_keys ~w(overall groups)
  @threshold_keys ~w(pass_rate threshold)
  @group_keys ~w(by pass_rate threshold)
  @resolved_keys ~w(datasets repeat pass_rule strict threshold group_by group_threshold)a

  @type pass_rule :: :all | :any | :majority | {:rate, float()}

  @type t :: %{
          version: 1,
          datasets: [String.t()],
          sampling: %{optional(:repeat) => pos_integer(), optional(:pass_rule) => pass_rule()},
          gates: %{
            optional(:overall) => %{threshold: float()},
            optional(:groups) => %{by: String.t(), threshold: float()}
          }
        }

  @doc """
  Loads a YAML policy from `path`.

  `:cwd` controls both policy and dataset path expansion. Set
  `allow_empty_datasets: true` when positional CLI datasets will be supplied to
  `resolve/3` later.
  """
  @spec load(Path.t(), keyword()) :: {:ok, t()} | {:error, String.t()}
  def load(path, opts \\ []) when is_binary(path) do
    cwd = cwd(opts)
    policy_path = Path.expand(path, cwd)

    case File.read(policy_path) do
      {:ok, content} ->
        parse(content, Keyword.put(opts, :cwd, cwd))

      {:error, reason} ->
        {:error, "could not read policy #{policy_path}: #{:file.format_error(reason)}"}
    end
  end

  @doc """
  Parses YAML policy content into the normalized policy shape.
  """
  @spec parse(String.t(), keyword()) :: {:ok, t()} | {:error, String.t()}
  def parse(content, opts \\ []) when is_binary(content) do
    with {:ok, decoded} <- decode_yaml(content), do: normalize_policy(decoded, opts)
  end

  @doc """
  Resolves runtime settings with `explicit` values taking precedence over the
  policy, and policy values taking precedence over `defaults`.

  A nonempty explicit `:datasets` list represents positional CLI files and
  replaces the policy dataset list rather than appending to it.
  """
  @spec resolve(t(), map() | keyword(), map() | keyword()) ::
          {:ok, map()} | {:error, String.t()}
  def resolve(policy, explicit, defaults \\ %{}) when is_map(policy) do
    explicit = to_map(explicit)
    defaults = to_map(defaults)

    with :ok <- reject_unknown_runtime_keys(explicit, "explicit settings"),
         :ok <- reject_unknown_runtime_keys(defaults, "defaults"),
         {:ok, settings} <- merge_settings(policy, explicit, defaults),
         {:ok, settings} <- normalize_runtime_settings(settings),
         :ok <- validate_strict_threshold(settings) do
      {:ok, settings}
    end
  end

  defp decode_yaml(content) do
    case YamlElixir.read_from_string(content) do
      {:ok, decoded} -> {:ok, decoded}
      {:error, reason} -> {:error, "invalid policy YAML: #{inspect(reason)}"}
    end
  rescue
    error -> {:error, "invalid policy YAML: #{Exception.message(error)}"}
  end

  defp normalize_policy(policy, opts) when is_map(policy) do
    with :ok <- reject_unknown_keys(policy, @top_level_keys, "policy"),
         :ok <- validate_version(Map.get(policy, "version")),
         {:ok, datasets} <- normalize_datasets(Map.get(policy, "datasets"), opts),
         {:ok, sampling} <- normalize_sampling(Map.get(policy, "sampling")),
         {:ok, gates} <- normalize_gates(Map.get(policy, "gates")) do
      {:ok, %{version: @version, datasets: datasets, sampling: sampling, gates: gates}}
    end
  end

  defp normalize_policy(_policy, _opts), do: {:error, "policy must be a YAML map"}

  defp validate_version(@version), do: :ok
  defp validate_version(nil), do: {:error, "policy version is required"}

  defp validate_version(version),
    do: {:error, "unsupported policy version #{inspect(version)}; expected #{@version}"}

  defp normalize_datasets(value, opts) when value in [nil, []] do
    if Keyword.get(opts, :allow_empty_datasets, false) do
      {:ok, []}
    else
      {:error, "datasets must be a nonempty list of paths"}
    end
  end

  defp normalize_datasets(datasets, opts) when is_list(datasets) do
    if Enum.all?(datasets, &(is_binary(&1) and String.trim(&1) != "")) do
      {:ok, Enum.map(datasets, &Path.expand(&1, cwd(opts)))}
    else
      {:error, "datasets must be a nonempty list of nonempty string paths"}
    end
  end

  defp normalize_datasets(_datasets, _opts),
    do: {:error, "datasets must be a nonempty list of nonempty string paths"}

  defp normalize_sampling(nil), do: {:ok, %{}}

  defp normalize_sampling(sampling) when is_map(sampling) do
    with :ok <- reject_unknown_keys(sampling, @sampling_keys, "sampling"),
         {:ok, repeat} <- normalize_optional_repeat(Map.get(sampling, "repeat")),
         {:ok, pass_rule} <- normalize_optional_pass_rule(Map.get(sampling, "pass_rule")) do
      {:ok, compact(%{repeat: repeat, pass_rule: pass_rule})}
    end
  end

  defp normalize_sampling(_sampling), do: {:error, "sampling must be a map"}

  defp normalize_optional_repeat(nil), do: {:ok, nil}
  defp normalize_optional_repeat(repeat) when is_integer(repeat) and repeat > 0, do: {:ok, repeat}

  defp normalize_optional_repeat(_repeat),
    do: {:error, "sampling.repeat must be a positive integer"}

  defp normalize_optional_pass_rule(nil), do: {:ok, nil}
  defp normalize_optional_pass_rule(pass_rule), do: normalize_pass_rule(pass_rule)

  defp normalize_pass_rule(rule) when rule in [:all, :any, :majority], do: {:ok, rule}
  defp normalize_pass_rule("all"), do: {:ok, :all}
  defp normalize_pass_rule("any"), do: {:ok, :any}
  defp normalize_pass_rule("majority"), do: {:ok, :majority}

  defp normalize_pass_rule({:rate, rate}), do: normalize_rate_rule(rate)

  defp normalize_pass_rule(rule) when is_map(rule) do
    with :ok <- reject_unknown_keys(rule, @rate_keys, "sampling.pass_rule"),
         true <- Map.has_key?(rule, "rate") || {:error, "sampling.pass_rule.rate is required"} do
      normalize_rate_rule(Map.get(rule, "rate"))
    end
  end

  defp normalize_pass_rule(_rule),
    do: {:error, "sampling.pass_rule must be all, any, majority, or a rate map"}

  defp normalize_rate_rule(rate) do
    case normalize_threshold(rate, "sampling.pass_rule.rate") do
      {:ok, rate} -> {:ok, {:rate, rate}}
      error -> error
    end
  end

  defp normalize_gates(nil), do: {:ok, %{}}

  defp normalize_gates(gates) when is_map(gates) do
    with :ok <- reject_unknown_keys(gates, @gate_keys, "gates"),
         {:ok, overall} <- normalize_overall_gate(Map.get(gates, "overall")),
         {:ok, groups} <- normalize_group_gate(Map.get(gates, "groups")) do
      {:ok, compact(%{overall: overall, groups: groups})}
    end
  end

  defp normalize_gates(_gates), do: {:error, "gates must be a map"}

  defp normalize_overall_gate(nil), do: {:ok, nil}

  defp normalize_overall_gate(overall) when is_map(overall) do
    with :ok <- reject_unknown_keys(overall, @threshold_keys, "gates.overall"),
         {:ok, threshold} <- required_threshold(overall, "gates.overall") do
      {:ok, %{threshold: threshold}}
    end
  end

  defp normalize_overall_gate(_overall), do: {:error, "gates.overall must be a map"}

  defp normalize_group_gate(nil), do: {:ok, nil}

  defp normalize_group_gate(groups) when is_map(groups) do
    with :ok <- reject_unknown_keys(groups, @group_keys, "gates.groups"),
         {:ok, by} <- normalize_group_field(Map.get(groups, "by")),
         {:ok, threshold} <- required_threshold(groups, "gates.groups") do
      {:ok, %{by: by, threshold: threshold}}
    end
  end

  defp normalize_group_gate(_groups), do: {:error, "gates.groups must be a map"}

  defp normalize_group_field(by) when is_binary(by) do
    if String.trim(by) == "" do
      {:error, "gates.groups.by must be a nonempty string"}
    else
      {:ok, by}
    end
  end

  defp normalize_group_field(_by), do: {:error, "gates.groups.by must be a nonempty string"}

  defp required_threshold(config, location) do
    pass_rate? = Map.has_key?(config, "pass_rate")
    threshold? = Map.has_key?(config, "threshold")

    cond do
      pass_rate? and threshold? ->
        {:error, "#{location} cannot set both pass_rate and threshold"}

      pass_rate? ->
        normalize_threshold(Map.get(config, "pass_rate"), "#{location}.pass_rate")

      threshold? ->
        normalize_threshold(Map.get(config, "threshold"), "#{location}.threshold")

      true ->
        {:error, "#{location}.threshold is required"}
    end
  end

  defp normalize_threshold(value, _location)
       when is_number(value) and value >= 0 and value <= 1,
       do: {:ok, value * 1.0}

  defp normalize_threshold(_value, location),
    do: {:error, "#{location} must be a number between 0.0 and 1.0"}

  defp merge_settings(policy, explicit, defaults) do
    policy_settings = %{
      datasets: policy.datasets,
      repeat: Map.get(policy.sampling, :repeat),
      pass_rule: Map.get(policy.sampling, :pass_rule),
      threshold: policy.gates |> Map.get(:overall, %{}) |> Map.get(:threshold),
      group_by: policy.gates |> Map.get(:groups, %{}) |> Map.get(:by),
      group_threshold: policy.gates |> Map.get(:groups, %{}) |> Map.get(:threshold)
    }

    datasets = first_nonempty_datasets(explicit, policy, defaults)

    settings =
      defaults
      |> overlay(policy_settings)
      |> overlay(Map.delete(explicit, :datasets))
      |> Map.put(:datasets, datasets)

    {:ok, settings}
  end

  defp normalize_runtime_settings(settings) do
    with {:ok, datasets} <- normalize_runtime_datasets(Map.get(settings, :datasets)),
         {:ok, repeat} <- normalize_runtime_repeat(Map.get(settings, :repeat, 1)),
         {:ok, pass_rule} <- normalize_pass_rule(Map.get(settings, :pass_rule, :all)),
         {:ok, strict} <- normalize_strict(Map.get(settings, :strict, false)),
         {:ok, threshold} <-
           normalize_optional_runtime_threshold(Map.get(settings, :threshold), "threshold"),
         {:ok, group_by} <- normalize_optional_group_by(Map.get(settings, :group_by)),
         {:ok, group_threshold} <-
           normalize_optional_runtime_threshold(
             Map.get(settings, :group_threshold),
             "group_threshold"
           ),
         :ok <- validate_group_pair(group_by, group_threshold) do
      {:ok,
       %{
         datasets: datasets,
         repeat: repeat,
         pass_rule: pass_rule,
         strict: strict,
         threshold: threshold,
         group_by: group_by,
         group_threshold: group_threshold
       }}
    end
  end

  defp normalize_runtime_datasets(datasets) when is_list(datasets) and datasets != [] do
    if Enum.all?(datasets, &(is_binary(&1) and String.trim(&1) != "")) do
      {:ok, Enum.map(datasets, &Path.expand/1)}
    else
      {:error, "datasets must be a nonempty list of nonempty string paths"}
    end
  end

  defp normalize_runtime_datasets(_datasets),
    do: {:error, "datasets must be a nonempty list of nonempty string paths"}

  defp normalize_runtime_repeat(repeat) when is_integer(repeat) and repeat > 0, do: {:ok, repeat}
  defp normalize_runtime_repeat(_repeat), do: {:error, "repeat must be a positive integer"}

  defp normalize_strict(strict) when is_boolean(strict), do: {:ok, strict}
  defp normalize_strict(_strict), do: {:error, "strict must be a boolean"}

  defp normalize_optional_runtime_threshold(nil, _location), do: {:ok, nil}

  defp normalize_optional_runtime_threshold(value, location),
    do: normalize_threshold(value, location)

  defp normalize_optional_group_by(nil), do: {:ok, nil}
  defp normalize_optional_group_by(value), do: normalize_group_field(value)

  defp validate_group_pair(nil, nil), do: :ok

  defp validate_group_pair(nil, _threshold),
    do: {:error, "group_by is required with group_threshold"}

  defp validate_group_pair(_by, nil), do: {:error, "group_threshold is required with group_by"}
  defp validate_group_pair(_by, _threshold), do: :ok

  defp validate_strict_threshold(%{strict: true, threshold: threshold}) when is_number(threshold),
    do: {:error, "strict cannot be combined with threshold"}

  defp validate_strict_threshold(_settings), do: :ok

  defp reject_unknown_runtime_keys(settings, location) do
    unknown = Map.keys(settings) -- @resolved_keys

    case unknown do
      [] -> :ok
      keys -> {:error, "unknown #{location} keys: #{format_keys(keys)}"}
    end
  end

  defp reject_unknown_keys(config, allowed, location) do
    unknown = Map.keys(config) -- allowed

    case unknown do
      [] -> :ok
      keys -> {:error, "unknown #{location} keys: #{format_keys(keys)}"}
    end
  end

  defp overlay(base, overrides) do
    Enum.reduce(overrides, base, fn
      {_key, nil}, acc -> acc
      {key, value}, acc -> Map.put(acc, key, value)
    end)
  end

  defp compact(map), do: Map.reject(map, fn {_key, value} -> is_nil(value) end)

  defp first_nonempty_datasets(explicit, policy, defaults) do
    Enum.find_value(
      [Map.get(explicit, :datasets), policy.datasets, Map.get(defaults, :datasets)],
      [],
      fn
        datasets when is_list(datasets) and datasets != [] -> datasets
        _other -> nil
      end
    )
  end

  defp to_map(value) when is_map(value), do: value
  defp to_map(value) when is_list(value), do: Map.new(value)

  defp cwd(opts), do: Keyword.get_lazy(opts, :cwd, &File.cwd!/0)

  defp format_keys(keys) do
    keys
    |> Enum.sort_by(&inspect/1)
    |> Enum.map_join(", ", &inspect/1)
  end
end
