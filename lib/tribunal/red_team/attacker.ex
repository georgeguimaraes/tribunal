defmodule Tribunal.RedTeam.Attacker do
  @moduledoc """
  Behaviour for the LLM that generates adversarial prompts.

  Plugins call `generate/3` with a meta-prompt and a NimbleOptions-style schema
  describing the expected attack list. Different implementations swap the
  underlying client without touching plugin code.

  ## Configuration

      config :tribunal, :red_team_attacker, Tribunal.RedTeam.Attacker.ReqLLM
      config :tribunal, :red_team_attacker_model, "anthropic:claude-sonnet-4-6"

  Default is `Tribunal.RedTeam.Attacker.ReqLLM` (used when `req_llm` is loaded).
  Tests typically use `Tribunal.RedTeam.Attacker.Stub` with seeded responses.

  ## Implementing a custom attacker

      defmodule MyApp.RedTeam.Attacker do
        @behaviour Tribunal.RedTeam.Attacker

        @impl true
        def generate(prompt, schema, opts) do
          # call your model, return {:ok, %{key => value}} or {:error, reason}
        end
      end
  """

  @callback generate(prompt :: String.t(), schema :: keyword(), opts :: keyword()) ::
              {:ok, map()} | {:error, term()}

  @default_module Tribunal.RedTeam.Attacker.ReqLLM

  @doc "Returns the configured default attacker module."
  def default, do: Application.get_env(:tribunal, :red_team_attacker, @default_module)
end
