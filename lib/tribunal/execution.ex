defmodule Tribunal.Execution do
  @moduledoc false

  alias Tribunal.{Evaluator, TestCase}

  @spec run((-> term()), TestCase.t(), list() | map(), keyword()) :: Evaluator.result()
  def run(callback, %TestCase{} = test_case, assertions, opts \\ [])
      when is_function(callback, 0) do
    started_at = System.monotonic_time(:millisecond)

    case TestCase.validate(test_case) do
      :ok -> invoke(callback, test_case, assertions, opts, started_at)
      {:error, reason} -> evaluation_error(test_case, assertions, reason, :input, started_at)
    end
  end

  defp invoke(callback, test_case, assertions, opts, started_at) do
    callback
    |> safe_call()
    |> normalize(test_case)
    |> case do
      {:ok, populated_case} ->
        Evaluator.evaluate(populated_case, assertions,
          defaults: Keyword.get(opts, :defaults, []),
          started_at: started_at
        )

      {:error, reason, kind} ->
        evaluation_error(test_case, assertions, reason, kind, started_at)
    end
  end

  defp safe_call(callback) do
    {:returned, callback.()}
  rescue
    exception -> {:raised, exception}
  catch
    kind, reason -> {:caught, kind, reason}
  end

  defp normalize({:returned, output}, test_case) when is_binary(output) do
    {:ok, TestCase.with_output(test_case, output)}
  end

  defp normalize({:returned, {:ok, output}}, test_case) when is_binary(output) do
    {:ok, TestCase.with_output(test_case, output)}
  end

  defp normalize(
         {:returned, %TestCase{actual_output: output} = returned_case},
         _test_case
       )
       when is_binary(output),
       do: {:ok, returned_case}

  defp normalize(
         {:returned, {:ok, %TestCase{actual_output: output} = returned_case}},
         _test_case
       )
       when is_binary(output),
       do: {:ok, returned_case}

  defp normalize({:returned, %TestCase{actual_output: output}}, _test_case),
    do: invalid_test_case_output(output)

  defp normalize({:returned, {:ok, %TestCase{actual_output: output}}}, _test_case),
    do: invalid_test_case_output(output)

  defp normalize({:returned, {:error, reason}}, _test_case), do: {:error, reason, :provider}

  defp normalize({:returned, output}, _test_case) do
    {:error,
     "provider must return a binary, {:ok, binary}, {:error, reason}, or Tribunal.TestCase; got: #{inspect(output)}",
     :provider}
  end

  defp normalize({:raised, exception}, _test_case), do: {:error, exception, :provider}

  defp normalize({:caught, kind, reason}, _test_case),
    do: {:error, "provider #{kind}: #{inspect(reason)}", :provider}

  defp invalid_test_case_output(output) do
    {:error,
     "provider-returned Tribunal.TestCase must have a binary actual_output; got: #{inspect(output)}",
     :provider}
  end

  defp evaluation_error(test_case, assertions, reason, kind, started_at) do
    Evaluator.error(test_case, reason,
      assertions: assertions,
      kind: kind,
      started_at: started_at
    )
  end
end
