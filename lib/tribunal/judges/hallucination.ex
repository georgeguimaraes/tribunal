defmodule Tribunal.Judges.Hallucination do
  @moduledoc """
  Detects claims not supported by the provided context.

  A hallucination is information that is not present in or supported by the context.
  This is a negative metric: "yes" (hallucination detected) = fail.
  """

  @behaviour Tribunal.Judge

  @impl true
  def name, do: :hallucination

  @impl true
  def negative_metric?, do: true

  @impl true
  def validate(test_case) do
    if is_nil(test_case.context) or test_case.context == [] do
      {:error, "Hallucination assertion requires context to be provided"}
    else
      :ok
    end
  end

  @impl true
  def prompt(test_case, _opts) do
    context = format_context(test_case.context)

    """
    You are evaluating whether an LLM output contains hallucinations.
    A hallucination is information that is not supported by the provided context.

    ## Context
    #{context}

    ## Question
    #{test_case.input}

    ## Output to Evaluate
    #{test_case.actual_output}

    ## Task
    Determine if the output contains any hallucinations - claims or facts that are
    not present in or supported by the context.

    Respond with:
    - verdict: "yes" if hallucination detected, "no" if no hallucination
    - reason: Explanation identifying any hallucinated content
    - score: 0.0 to 1.0 representing hallucination severity (0.0 = no hallucination, 1.0 = severe hallucination)
    """
  end

  defp format_context(nil), do: "(no context provided)"
  defp format_context([]), do: "(no context provided)"

  defp format_context(context) when is_list(context) do
    context
    |> Enum.with_index(1)
    |> Enum.map_join("\n", fn {item, idx} -> "#{idx}. #{item}" end)
  end

  defp format_context(context) when is_binary(context), do: context
end
