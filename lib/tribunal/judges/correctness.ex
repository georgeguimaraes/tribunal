defmodule Tribunal.Judges.Correctness do
  @moduledoc """
  Compares LLM output against an expected answer.

  Correctness means the output conveys the same meaning as the expected answer.
  Combines factual accuracy with semantic similarity: the output must be
  factually equivalent even if worded differently.
  """

  @behaviour Tribunal.Judge

  @impl true
  def name, do: :correctness

  @impl true
  def validate(test_case) do
    if is_nil(test_case.expected_output) do
      {:error, "Correctness assertion requires expected_output to be provided"}
    else
      :ok
    end
  end

  @impl true
  def prompt(test_case, _opts) do
    """
    You are evaluating whether an LLM output is correct compared to an expected answer.
    Correctness means the output conveys the same factual content and meaning.

    ## Question
    #{test_case.input}

    ## Expected Answer (Ground Truth)
    #{test_case.expected_output}

    ## Output to Evaluate
    #{test_case.actual_output}

    ## Evaluation Criteria

    ### Factual Correctness
    - Does the output contain the same facts as the expected answer?
    - Are numerical values, dates, names, and specifics accurate?
    - Does it avoid stating anything that contradicts the expected answer?

    ### Semantic Equivalence
    - Does the output convey the same meaning, even if worded differently?
    - Paraphrasing is acceptable if the meaning is preserved
    - Additional true information doesn't reduce correctness
    - Missing important information from the expected answer reduces correctness

    ### Scoring Guide
    - 1.0: Output is factually equivalent to expected answer
    - 0.7-0.9: Mostly correct with minor omissions or additions
    - 0.4-0.6: Partially correct, missing key information or has some errors
    - 0.1-0.3: Mostly incorrect but has some accurate elements
    - 0.0: Completely wrong or contradicts the expected answer

    ## Response Format
    Respond with:
    - verdict: "yes" if correct, "no" if incorrect, "partial" if partially correct
    - reason: Explain what matches and what differs from the expected answer
    - score: 0.0 to 1.0 based on the scoring guide above
    """
  end
end
