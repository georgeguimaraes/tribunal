defmodule Tribunal.Judges.Faithful do
  @moduledoc """
  Evaluates whether LLM output is grounded in provided context.

  Faithfulness means the output only contains information that can be derived
  from the context. Use for RAG systems, documentation assistants, etc.
  """

  @behaviour Tribunal.Judge

  @impl true
  def name, do: :faithful

  @impl true
  def validate(test_case) do
    if is_nil(test_case.context) or test_case.context == [] do
      {:error, "Faithful assertion requires context to be provided"}
    else
      :ok
    end
  end

  @impl true
  def prompt(test_case, _opts) do
    context = format_context(test_case.context)

    """
    You are evaluating whether an LLM output is faithful to the provided context.
    Faithfulness means the output only contains information that can be derived from the context.

    ## Context
    #{context}

    ## Question
    #{test_case.input}

    ## Output to Evaluate
    #{test_case.actual_output}

    ## Task
    Determine if the output is faithful to the context. The output should not contain
    claims or information that cannot be supported by the context.

    Respond with:
    - verdict: "yes" if faithful, "no" if not faithful, "partial" if partially faithful
    - reason: Explanation of your verdict
    - score: 0.0 to 1.0 representing faithfulness (1.0 = fully faithful)
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
