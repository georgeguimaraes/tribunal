defmodule Tribunal.Judges.Correctness do
  @moduledoc """
  Compares LLM output against an expected answer.

  Correctness means the output conveys the same meaning as the expected answer.
  Minor wording differences are acceptable if the meaning is preserved.
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
    Correctness means the output conveys the same meaning as the expected answer.

    ## Question
    #{test_case.input}

    ## Expected Answer
    #{test_case.expected_output}

    ## Output to Evaluate
    #{test_case.actual_output}

    ## Task
    Determine if the output is correct - does it convey the same meaning as the expected
    answer? Minor wording differences are acceptable if the meaning is the same.

    Respond with:
    - verdict: "yes" if correct, "no" if incorrect, "partial" if partially correct
    - reason: Explanation of your verdict
    - score: 0.0 to 1.0 representing correctness (1.0 = fully correct)
    """
  end
end
