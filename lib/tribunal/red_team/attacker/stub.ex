defmodule Tribunal.RedTeam.Attacker.Stub do
  @moduledoc """
  Stub attacker for tests. Returns canned responses set via `set_response/1`.

  State is per-process (stored in the process dictionary), so tests using this
  stub are async-safe.

  ## Usage

      Tribunal.RedTeam.Attacker.Stub.set_response(%{
        attacks: [
          %{prompt: "...", goal: "..."}
        ]
      })

      {:ok, response} = Tribunal.RedTeam.Attacker.Stub.generate(prompt, schema, [])
  """

  @behaviour Tribunal.RedTeam.Attacker

  @key :tribunal_attacker_stub_response

  @impl true
  def generate(_prompt, _schema, _opts) do
    case Process.get(@key) do
      nil -> {:error, "no stub response set; call Tribunal.RedTeam.Attacker.Stub.set_response/1"}
      response -> {:ok, response}
    end
  end

  @doc "Sets the canned response for the calling process."
  def set_response(response), do: Process.put(@key, response)

  @doc "Clears any canned response for the calling process."
  def clear, do: Process.delete(@key)
end
