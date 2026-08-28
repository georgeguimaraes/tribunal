defmodule Tribunal.RedTeam.Attacker.ReqLLM do
  @moduledoc """
  Default attacker LLM, backed by `req_llm`.

  Picks the model from `opts[:model]`, then `config :tribunal, :red_team_attacker_model`,
  then a strong-model default. Attack quality scales with the attacker's
  reasoning ability, so the default leans toward a frontier model rather than
  a small/fast one.
  """

  @behaviour Tribunal.RedTeam.Attacker

  @default_model "anthropic:claude-sonnet-4-5"

  @impl true
  def generate(prompt, schema, opts) do
    if Code.ensure_loaded?(ReqLLM) do
      do_generate(prompt, schema, opts)
    else
      {:error,
       "req_llm is not available. Add {:req_llm, \">= 1.2.0 and < 2.0.0\"} or configure a different attacker."}
    end
  end

  defp do_generate(prompt, schema, opts) do
    model =
      opts[:model] || Application.get_env(:tribunal, :red_team_attacker_model, @default_model)

    context = [apply(ReqLLM.Context, :user, [prompt])]
    llm_opts = Keyword.take(opts, [:temperature, :max_tokens])

    case apply(ReqLLM, :generate_object, [model, context, schema, llm_opts]) do
      {:ok, response} -> {:ok, apply(ReqLLM.Response, :object, [response])}
      {:error, error} -> {:error, inspect(error)}
    end
  end
end
