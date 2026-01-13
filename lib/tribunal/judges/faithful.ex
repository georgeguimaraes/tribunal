defmodule Tribunal.Judges.Faithful do
  @moduledoc """
  Evaluates whether LLM output is grounded in provided context.

  Faithfulness means the output only contains information that can be derived
  from the context. Use for RAG systems, documentation assistants, etc.

  Uses claim extraction approach: breaks output into claims, verifies each
  against context, scores based on proportion of supported claims.
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
    Faithfulness means every claim in the output can be derived from the context.

    ## Context
    #{context}

    ## Question
    #{test_case.input}

    ## Output to Evaluate
    #{test_case.actual_output}

    ## Evaluation Process
    1. Extract each distinct claim or statement from the output
    2. For each claim, determine if it can be inferred from the context
    3. Calculate the proportion of supported claims

    ## Criteria
    - A claim is SUPPORTED if it can be logically inferred from the context
    - A claim is UNSUPPORTED if it adds information not in the context
    - A claim is CONTRADICTED if it conflicts with the context
    - General knowledge (e.g., "the sky is blue") doesn't count against faithfulness
    - Paraphrasing context is acceptable if meaning is preserved

    ## Response Format
    Respond with:
    - verdict: "yes" if all substantive claims are supported, "no" if any claim contradicts
      or significantly adds to the context, "partial" if most but not all claims are supported
    - reason: List which claims are supported vs unsupported/contradicted
    - score: (supported claims) / (total claims), ranging 0.0 to 1.0
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
