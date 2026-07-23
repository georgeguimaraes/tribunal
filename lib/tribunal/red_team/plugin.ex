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
    case Enum.reject(keys, &Keyword.has_key?(opts, &1)) do
      [] -> {:ok, Enum.map(keys, &Keyword.fetch!(opts, &1))}
      missing -> {:error, {:missing_options, missing}}
    end
  end

  @doc """
  Extracts and validates the attacker's `attacks` list.

  Accepts the attacker response with an `attacks` list keyed by either string
  or atom. Every attack must carry a non-empty `prompt`; otherwise the whole
  batch is rejected with `{:error, {:invalid_attack, attack}}` rather than
  emitting a case with `input: nil`. An unrecognised shape returns
  `{:error, {:unexpected_attacker_response, other}}`.
  """
  def extract_attacks(%{"attacks" => attacks}) when is_list(attacks),
    do: validate_attacks(attacks)

  def extract_attacks(%{attacks: attacks}) when is_list(attacks), do: validate_attacks(attacks)
  def extract_attacks(other), do: {:error, {:unexpected_attacker_response, other}}

  defp validate_attacks(attacks) do
    case Enum.find(attacks, fn attack -> is_nil(attack_prompt(attack)) end) do
      nil -> {:ok, attacks}
      bad -> {:error, {:invalid_attack, bad}}
    end
  end

  defp attack_prompt(attack) when is_map(attack) do
    case attack["prompt"] || attack[:prompt] do
      value when is_binary(value) -> if String.trim(value) == "", do: nil, else: value
      _ -> nil
    end
  end

  defp attack_prompt(_), do: nil
end
