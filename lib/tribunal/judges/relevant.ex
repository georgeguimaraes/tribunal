defmodule Tribunal.Judges.Relevant do
  @moduledoc """
  Evaluates whether LLM output is relevant to the input query.

  Relevance means the output directly addresses and answers the question.
  Uses statement extraction: breaks output into statements, classifies each
  as relevant or irrelevant, scores based on proportion of relevant content.
  """

  @behaviour Tribunal.Judge

  @impl true
  def name, do: :relevant

  @impl true
  def prompt(test_case, _opts) do
    """
    You are evaluating whether an LLM output is relevant to the question asked.
    Relevance means the output directly addresses what the user is asking.

    ## Question/Input
    #{test_case.input}

    ## Output to Evaluate
    #{test_case.actual_output}

    ## Evaluation Process
    1. Identify the user's core question or intent
    2. Extract each statement from the output
    3. Classify each statement as relevant or irrelevant to the question
    4. Calculate the proportion of relevant statements

    ## Relevance Criteria
    A statement is RELEVANT if it:
    - Directly answers the question
    - Provides necessary context for the answer
    - Clarifies or elaborates on the answer
    - Addresses a reasonable interpretation of the question

    A statement is IRRELEVANT if it:
    - Goes off-topic entirely
    - Addresses a different question
    - Provides unnecessary information unrelated to the query
    - Contains filler or padding that doesn't serve the answer

    ## Edge Cases
    - Partial answers: If the output addresses some but not all aspects of a multi-part
      question, it's "partial"
    - Refusals: A polite refusal that explains why is relevant if the question is inappropriate
    - Tangential info: Brief relevant context is acceptable; extensive tangents are not

    ## Response Format
    Respond with:
    - verdict: "yes" if output addresses the question, "no" if off-topic,
      "partial" if only partly addresses it
    - reason: Explain what makes the output relevant or irrelevant
    - score: (relevant statements) / (total statements), ranging 0.0 to 1.0
    """
  end
end
