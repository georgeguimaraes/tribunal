defmodule Tribunal.Judge do
  @moduledoc """
  Behaviour for LLM-as-judge assertions.

  All judges (built-in and custom) implement this behaviour. This provides
  a consistent interface for evaluation criteria.

  ## Example

      defmodule MyApp.Judges.BrandVoice do
        @behaviour Tribunal.Judge

        @impl true
        def name, do: :brand_voice

        @impl true
        def prompt(test_case, _opts) do
          \"""
          Evaluate if the response matches our brand voice guidelines:

          - Friendly but professional tone
          - No jargon or technical terms
          - Empathetic and helpful

          Response to evaluate:
          \#{test_case.actual_output}

          Query: \#{test_case.input}
          \"""
        end
      end

  ## Configuration

  Register your custom judges in config:

      config :tribunal, :custom_judges, [
        MyApp.Judges.BrandVoice,
        MyApp.Judges.Compliance
      ]

  Then use them like built-in assertions:

      assert_judge :brand_voice, response, query: input
  """

  alias Tribunal.TestCase

  @doc """
  Returns the atom name for this judge.

  This name is used to invoke the judge in assertions:

      assert_judge :my_judge_name, response, opts
  """
  @callback name() :: atom()

  @doc """
  Builds the evaluation prompt for the LLM judge.

  Receives the test case and any options passed to the assertion.
  Should return a prompt string that asks the LLM to evaluate
  the response and return a JSON verdict.

  The prompt should instruct the LLM to return JSON with:
  - `verdict`: "yes", "no", or "partial"
  - `reason`: explanation for the verdict
  - `score`: confidence score 0.0-1.0
  """
  @callback prompt(test_case :: TestCase.t(), opts :: keyword()) :: String.t()

  @doc """
  Optional: validate that the test case has required fields.

  Return `:ok` if valid, or `{:error, reason}` if not.
  Default implementation always returns `:ok`.
  """
  @callback validate(test_case :: TestCase.t()) :: :ok | {:error, String.t()}

  @doc """
  Optional: whether "no" verdict means pass (for negative metrics like toxicity).

  When true, verdict "no" = pass and "yes" = fail.
  When false (default), verdict "yes" = pass and "no" = fail.
  """
  @callback negative_metric?() :: boolean()

  @doc """
  Optional: customize how the LLM result is interpreted.

  By default, uses verdict and threshold logic. Override for custom pass/fail logic.

  Should return `{:pass, details}` or `{:fail, details}`.
  """
  @callback evaluate_result(result :: map(), opts :: keyword()) ::
              {:pass, map()} | {:fail, map()}

  @optional_callbacks [validate: 1, negative_metric?: 0, evaluate_result: 2]

  # Built-in judges
  @builtin_judges [
    Tribunal.Judges.Faithful,
    Tribunal.Judges.Relevant,
    Tribunal.Judges.Hallucination,
    Tribunal.Judges.Correctness,
    Tribunal.Judges.Bias,
    Tribunal.Judges.Toxicity,
    Tribunal.Judges.Harmful,
    Tribunal.Judges.Jailbreak,
    Tribunal.Judges.PII
  ]

  @doc """
  Returns all built-in judge modules.
  """
  def builtin_judges, do: @builtin_judges

  @doc """
  Returns all configured custom judge modules.
  """
  def custom_judges do
    Application.get_env(:tribunal, :custom_judges, [])
  end

  @doc """
  Returns all judge modules (built-in + custom).
  """
  def all_judges do
    @builtin_judges ++ custom_judges()
  end

  @doc """
  Finds a judge module by name.

  Returns `{:ok, module}` or `:error`.
  """
  def find(name) when is_atom(name) do
    all_judges()
    |> Enum.find(fn module -> module.name() == name end)
    |> case do
      nil -> :error
      module -> {:ok, module}
    end
  end

  @doc """
  Returns list of all judge names (built-in + custom).
  """
  def all_judge_names do
    Enum.map(all_judges(), & &1.name())
  end

  @doc """
  Returns list of built-in judge names.
  """
  def builtin_judge_names do
    Enum.map(@builtin_judges, & &1.name())
  end

  @doc """
  Returns list of custom judge names.
  """
  def custom_judge_names do
    Enum.map(custom_judges(), & &1.name())
  end

  @doc """
  Checks if a name is a registered custom judge.
  """
  def custom_judge?(name) when is_atom(name) do
    name in custom_judge_names()
  end

  @doc """
  Checks if a name is a built-in judge.
  """
  def builtin_judge?(name) when is_atom(name) do
    name in builtin_judge_names()
  end
end
