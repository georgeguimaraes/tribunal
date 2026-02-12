defmodule Tribunal.Assertions.Judge do
  @moduledoc """
  LLM-as-judge assertions for evaluating LLM outputs.

  Requires `req_llm` dependency. Uses structured output to get consistent
  verdicts from the judge model.
  """

  @default_model "anthropic:claude-3-5-haiku-latest"
  @default_threshold 0.8

  @schema [
    verdict: [type: :string, required: true],
    reason: [type: :string, required: true],
    score: [type: :float]
  ]

  @doc """
  Returns list of available judge assertion types.
  """
  def available do
    Tribunal.Judge.all_judge_names()
  end

  @doc """
  Evaluates a judge assertion against a test case.
  """
  def evaluate(type, test_case, opts) when is_atom(type) do
    case Tribunal.Judge.find(type) do
      {:ok, module} ->
        with :ok <- validate_test_case(module, test_case) do
          run_judge(module, test_case, opts)
        end

      :error ->
        {:error, "Unknown judge assertion: #{type}"}
    end
  end

  defp validate_test_case(module, test_case) do
    if function_exported?(module, :validate, 1) do
      module.validate(test_case)
    else
      :ok
    end
  end

  defp run_judge(module, test_case, opts) do
    model = opts[:model] || Application.get_env(:tribunal, :llm, @default_model)
    threshold = opts[:threshold] || @default_threshold
    prompt = module.prompt(test_case, opts)

    messages = [
      %{role: "system", content: system_prompt()},
      %{role: "user", content: prompt}
    ]

    case call_llm(model, messages, opts) do
      {:ok, response} ->
        if function_exported?(module, :evaluate_result, 2) do
          module.evaluate_result(response, opts)
        else
          negative_metric? =
            function_exported?(module, :negative_metric?, 0) and module.negative_metric?()

          interpret_response(response, threshold, negative_metric?)
        end

      {:error, reason} ->
        {:error, to_string(reason)}
    end
  end

  defp system_prompt do
    """
    You are a precise evaluator of LLM outputs. Your task is to assess outputs
    based on specific criteria and provide structured verdicts.

    Always respond with valid JSON containing:
    - verdict: "yes", "no", or "partial"
    - reason: A brief explanation
    - score: A float from 0.0 to 1.0

    Be objective and consistent in your evaluations.
    """
  end

  defp call_llm(model, messages, opts) do
    # Allow injecting custom LLM for tests via opts[:llm]
    case opts[:llm] do
      nil ->
        call_req_llm(model, messages, opts)

      llm_fn when is_function(llm_fn, 3) ->
        llm_fn.(model, messages, opts)
    end
  end

  defp call_req_llm(model, messages, opts) do
    if Code.ensure_loaded?(ReqLLM) do
      context =
        Enum.map(messages, fn
          %{role: "system", content: content} -> apply(ReqLLM.Context, :system, [content])
          %{role: "user", content: content} -> apply(ReqLLM.Context, :user, [content])
          %{role: "assistant", content: content} -> apply(ReqLLM.Context, :assistant, [content])
        end)

      llm_opts = Keyword.take(opts, [:temperature, :max_tokens])

      case apply(ReqLLM, :generate_object, [model, context, @schema, llm_opts]) do
        {:ok, response} ->
          {:ok, apply(ReqLLM.Response, :object, [response])}

        {:error, error} ->
          {:error, inspect(error)}
      end
    else
      {:error, "req_llm is not available. Add {:req_llm, \"~> 1.2\"} to your dependencies."}
    end
  end

  defp interpret_response(response, threshold, negative_metric?) do
    details = %{
      verdict: response["verdict"],
      reason: response["reason"],
      score: response["score"]
    }

    verdict_result(response["verdict"], response["score"], threshold, negative_metric?, details)
  end

  defp verdict_result("no", _score, _threshold, true, details), do: {:pass, details}
  defp verdict_result("yes", _score, _threshold, true, details), do: {:fail, details}
  defp verdict_result("yes", _score, _threshold, false, details), do: {:pass, details}
  defp verdict_result("no", _score, _threshold, false, details), do: {:fail, details}

  defp verdict_result("partial", score, threshold, _negative?, details)
       when is_number(score) and score >= threshold do
    {:pass, details}
  end

  defp verdict_result("partial", _score, _threshold, _negative?, details), do: {:fail, details}

  defp verdict_result(verdict, _score, _threshold, _negative?, _details),
    do: {:error, "Unexpected verdict: #{verdict}"}
end
