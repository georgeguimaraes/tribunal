defmodule Tribunal.Judges.Relevant do
  @moduledoc """
  Evaluates whether LLM output is relevant to the input query.

  Relevance means the output directly addresses and answers the question.
  """

  @behaviour Tribunal.Judge

  @impl true
  def name, do: :relevant

  @impl true
  def prompt(test_case, _opts) do
    """
    You are evaluating whether an LLM output is relevant to the question asked.
    Relevance means the output directly addresses and answers the question.

    ## Question
    #{test_case.input}

    ## Output to Evaluate
    #{test_case.actual_output}

    ## Task
    Determine if the output is relevant to the question. The output should directly
    address what was asked, not go off-topic or provide unrelated information.

    Respond with:
    - verdict: "yes" if relevant, "no" if not relevant, "partial" if partially relevant
    - reason: Explanation of your verdict
    - score: 0.0 to 1.0 representing relevance (1.0 = fully relevant)
    """
  end
end
