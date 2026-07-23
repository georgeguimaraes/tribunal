defmodule Tribunal.RedTeam.Plugin.Base do
  @moduledoc """
  Shared implementation for the built-in LLM-driven red-team plugins.

  `use Tribunal.RedTeam.Plugin.Base` injects `id/0`, `severity/0`, and a full
  `generate/1` pipeline: required-option validation, the plugin and attacker
  telemetry spans, the attacker call, attack extraction, and per-case emission.
  The using module supplies only the parts that differ between plugins:

    * `meta_prompt/1` — build the attacker meta-prompt from the call opts
      (`:purpose`, `:count`, and any plugin-specific keys like `:policy`).
    * `expected/1` — build the `expected` clause carried into each generated
      case (the assertion the judge runs against the target's response).
    * `goal_description/0` — the schema description for each attack's `goal`.

  ## Options

    * `:id` — required. The plugin id atom.
    * `:severity` — required. `:low`, `:medium`, or `:high`.
    * `:required` — required option keys, validated before generation.
      Defaults to `[:purpose]`.
    * `:default_count` — attacks per call when `:count` is absent. Defaults to 5.

  ## Example

      defmodule MyApp.RedTeam.Plugins.Custom do
        use Tribunal.RedTeam.Plugin.Base, id: :custom, severity: :medium

        @impl true
        def meta_prompt(opts), do: "Attack \#{opts[:purpose]} ..."

        @impl true
        def expected(opts), do: %{custom: %{purpose: opts[:purpose]}}

        @impl true
        def goal_description, do: "One sentence on what the attack elicits."
      end
  """

  alias Tribunal.RedTeam.Plugin

  @type opts :: keyword()

  @callback meta_prompt(opts()) :: String.t()
  @callback expected(opts()) :: map()
  @callback goal_description() :: String.t()

  defmacro __using__(macro_opts) do
    id = Keyword.fetch!(macro_opts, :id)
    severity = Keyword.fetch!(macro_opts, :severity)
    required = Keyword.get(macro_opts, :required, [:purpose])
    default_count = Keyword.get(macro_opts, :default_count, 5)

    quote do
      @behaviour Tribunal.RedTeam.Plugin
      @behaviour Tribunal.RedTeam.Plugin.Base

      alias Tribunal.RedTeam.Attacker
      alias Tribunal.RedTeam.Plugin
      alias Tribunal.RedTeam.Plugin.Base

      @impl Tribunal.RedTeam.Plugin
      def id, do: unquote(id)

      @impl Tribunal.RedTeam.Plugin
      def severity, do: unquote(severity)

      @impl Tribunal.RedTeam.Plugin
      def generate(opts) do
        with {:ok, _values} <- Plugin.fetch_required(opts, unquote(required)) do
          count = Keyword.get(opts, :count, unquote(default_count))
          opts = Keyword.put(opts, :count, count)
          attacker = Keyword.get(opts, :attacker, Attacker.default())

          :telemetry.span(
            [:tribunal, :red_team, :plugin],
            %{plugin: id(), count_requested: count},
            fn ->
              result = Base.run(__MODULE__, attacker, opts)
              {result, %{plugin: id(), count_returned: Base.result_count(result)}}
            end
          )
        end
      end
    end
  end

  @doc false
  def run(module, attacker, opts) do
    with {:ok, raw} <- call_attacker(module, attacker, opts),
         {:ok, attacks} <- Plugin.extract_attacks(raw) do
      expected = module.expected(opts)
      purpose = Keyword.get(opts, :purpose)
      cases = Enum.map(attacks, &to_case(module, &1, purpose, expected))
      Enum.each(cases, &emit_case_event/1)
      {:ok, cases}
    end
  end

  @doc false
  def result_count({:ok, cases}), do: length(cases)
  def result_count(_), do: 0

  defp call_attacker(module, attacker, opts) do
    prompt = module.meta_prompt(opts)
    schema = schema(module.goal_description())

    :telemetry.span(
      [:tribunal, :red_team, :attacker_llm],
      %{plugin: module.id(), model: opts[:model]},
      fn -> {attacker.generate(prompt, schema, opts), %{}} end
    )
  end

  defp to_case(module, attack, purpose, expected) do
    %{
      input: attack_field(attack, "prompt"),
      metadata: %{
        plugin: module.id(),
        severity: module.severity(),
        goal: attack_field(attack, "goal"),
        purpose: purpose
      },
      expected: expected
    }
  end

  defp attack_field(attack, key) when is_map(attack) do
    attack[key] || attack[String.to_atom(key)]
  end

  defp emit_case_event(case_) do
    :telemetry.execute(
      [:tribunal, :red_team, :case_emitted],
      %{count: 1},
      Map.take(case_.metadata, [:plugin, :severity, :goal])
    )
  end

  defp schema(goal_description) do
    %{
      "type" => "object",
      "additionalProperties" => false,
      "required" => ["attacks"],
      "properties" => %{
        "attacks" => %{
          "type" => "array",
          "items" => %{
            "type" => "object",
            "additionalProperties" => false,
            "required" => ["prompt", "goal"],
            "properties" => %{
              "prompt" => %{
                "type" => "string",
                "description" => "User message the attacker would send."
              },
              "goal" => %{
                "type" => "string",
                "description" => goal_description
              }
            }
          }
        }
      }
    }
  end
end
