defmodule Tribunal.RedTeam.Plugin do
  @moduledoc """
  Behaviour for red-team attack generators.

  A plugin produces a list of adversarial test cases targeted at a specific
  failure mode (policy violations, prompt extraction, hijacking, etc.). Each
  generated case is a regular Tribunal dataset entry with metadata identifying
  the plugin and an `expected` clause naming the assertion to run against the
  target's response.

  ## Implementing a plugin

      defmodule MyApp.RedTeam.Plugins.Custom do
        @behaviour Tribunal.RedTeam.Plugin

        @impl true
        def id, do: :custom

        @impl true
        def severity, do: :medium

        @impl true
        def generate(opts) do
          # ...
          {:ok, [%{input: ..., metadata: ..., expected: ...}, ...]}
        end
      end

  Built-in plugins live under `Tribunal.RedTeam.Plugins.*`. Custom plugins are
  registered via:

      config :tribunal, :red_team_plugins, [MyApp.RedTeam.Plugins.Custom]
  """

  @type case_t :: %{
          input: String.t(),
          metadata: map(),
          expected: keyword() | map()
        }

  @callback id() :: atom()
  @callback severity() :: :low | :medium | :high
  @callback generate(opts :: keyword()) :: {:ok, [case_t()]} | {:error, term()}

  @builtin_plugins [
    Tribunal.RedTeam.Plugins.Policy,
    Tribunal.RedTeam.Plugins.Hijacking,
    Tribunal.RedTeam.Plugins.PromptExtraction,
    Tribunal.RedTeam.Plugins.ExcessiveAgency,
    Tribunal.RedTeam.Plugins.Imitation,
    Tribunal.RedTeam.Plugins.Hallucination
  ]

  @doc "Returns built-in plugin modules."
  def builtin_plugins, do: @builtin_plugins

  @doc "Returns custom plugin modules registered via application config."
  def custom_plugins, do: Application.get_env(:tribunal, :red_team_plugins, [])

  @doc "Returns all plugin modules (built-in + custom)."
  def all_plugins, do: builtin_plugins() ++ custom_plugins()

  @doc """
  Finds a plugin module by its `id/0` value.

  Returns `{:ok, module}` or `:error`.
  """
  def find(id) when is_atom(id) do
    case Enum.find(all_plugins(), fn module -> module.id() == id end) do
      nil -> :error
      module -> {:ok, module}
    end
  end

  @doc "Returns the list of registered plugin ids."
  def all_ids, do: Enum.map(all_plugins(), & &1.id())

  @doc """
  Fetches required options, returning a friendly error instead of raising.

  Returns `{:ok, values}` with values in the same order as `keys`, or
  `{:error, {:missing_options, missing}}` listing every absent key. Plugins
  use this in `generate/1` so a missing required option surfaces as a
  `{:error, _}` the caller can handle, rather than a raw `KeyError`.
  """
  def fetch_required(opts, keys) do
    case Enum.reject(keys, &valid_required_option?(opts, &1)) do
      [] -> {:ok, Enum.map(keys, &Keyword.fetch!(opts, &1))}
      missing -> {:error, {:missing_options, missing}}
    end
  end

  defp valid_required_option?(opts, key) do
    case Keyword.fetch(opts, key) do
      {:ok, nil} -> false
      {:ok, value} when is_binary(value) -> String.trim(value) != ""
      {:ok, _value} -> true
      :error -> false
    end
  end

  @doc """
  Extracts and validates the attacker's `attacks` list.

  Accepts the attacker response with an `attacks` list keyed by either string
  or atom. Every attack must carry a non-empty `prompt` and `goal`. When an
  expected count is supplied, the batch must contain exactly that many unique
  prompts. An unrecognised shape returns
  `{:error, {:unexpected_attacker_response, other}}`.
  """
  def extract_attacks(response, expected_count \\ nil)

  def extract_attacks(%{"attacks" => attacks}, expected_count) when is_list(attacks),
    do: validate_attacks(attacks, expected_count)

  def extract_attacks(%{attacks: attacks}, expected_count) when is_list(attacks),
    do: validate_attacks(attacks, expected_count)

  def extract_attacks(other, _expected_count),
    do: {:error, {:unexpected_attacker_response, other}}

  defp validate_attacks(attacks, expected_count) do
    with :ok <- validate_attack_fields(attacks),
         :ok <- validate_attack_count(attacks, expected_count),
         :ok <- validate_unique_prompts(attacks) do
      {:ok, attacks}
    end
  end

  defp validate_attack_fields(attacks) do
    case Enum.find(attacks, fn attack ->
           is_nil(attack_field(attack, "prompt")) or is_nil(attack_field(attack, "goal"))
         end) do
      nil -> :ok
      bad -> {:error, {:invalid_attack, bad}}
    end
  end

  defp validate_attack_count(_attacks, nil), do: :ok

  defp validate_attack_count(attacks, expected_count) do
    actual_count = length(attacks)

    if actual_count == expected_count,
      do: :ok,
      else: {:error, {:unexpected_attack_count, expected_count, actual_count}}
  end

  defp validate_unique_prompts(attacks) do
    prompts = Enum.map(attacks, &attack_field(&1, "prompt"))

    case Enum.find(prompts, fn prompt -> Enum.count(prompts, &(&1 == prompt)) > 1 end) do
      nil -> :ok
      duplicate -> {:error, {:duplicate_prompt, duplicate}}
    end
  end

  defp attack_field(attack, key) when is_map(attack) do
    case attack[key] || attack[String.to_existing_atom(key)] do
      value when is_binary(value) ->
        case String.trim(value) do
          "" -> nil
          trimmed -> trimmed
        end

      _ ->
        nil
    end
  end

  defp attack_field(_attack, _key), do: nil
end
