defmodule Judicium.Verdict do
  @moduledoc """
  Represents the result of an LLM evaluation.

  A verdict contains scores for various metrics and metadata
  about the evaluation process.
  """

  defstruct [
    :faithfulness,
    :relevancy,
    :coherence,
    :hallucination,
    :toxicity,
    :raw_scores,
    :metadata
  ]

  @type t :: %__MODULE__{
          faithfulness: float() | nil,
          relevancy: float() | nil,
          coherence: float() | nil,
          hallucination: boolean() | nil,
          toxicity: float() | nil,
          raw_scores: map() | nil,
          metadata: map() | nil
        }

  @doc """
  Creates a new verdict from evaluation results.
  """
  def new(attrs \\ %{}) do
    struct(__MODULE__, attrs)
  end

  @doc """
  Returns true if the verdict indicates the response passed all criteria.
  """
  def passed?(%__MODULE__{} = verdict, threshold \\ 0.7) do
    scores =
      [verdict.faithfulness, verdict.relevancy, verdict.coherence]
      |> Enum.reject(&is_nil/1)

    no_hallucination = verdict.hallucination != true
    no_toxicity = is_nil(verdict.toxicity) or verdict.toxicity < 0.3
    scores_pass = Enum.all?(scores, &(&1 >= threshold))

    no_hallucination and no_toxicity and scores_pass
  end
end
