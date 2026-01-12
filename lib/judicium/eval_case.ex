defmodule Judicium.EvalCase do
  @moduledoc """
  ExUnit integration for LLM evaluations.

  ## Usage

      defmodule MyApp.RAGEvalTest do
        use ExUnit.Case
        use Judicium.EvalCase

        @moduletag :eval

        test "response is faithful" do
          response = MyApp.RAG.query("What's the return policy?")

          assert_contains response, "30 days"
          assert_faithful response, context: @docs, threshold: 0.8
          refute_hallucination response, context: @docs
        end
      end

  ## Dataset-Driven Tests

      defmodule MyApp.RAGEvalTest do
        use ExUnit.Case
        use Judicium.EvalCase

        @moduletag :eval

        judicium_eval "test/evals/datasets/questions.json",
          provider: {MyApp.RAG, :query}
      end

  Run with: `mix test --only eval`
  """

  defmacro __using__(_opts) do
    quote do
      import Judicium.EvalCase
      import Judicium.EvalCase.Assertions
    end
  end

  @doc """
  Generates tests from a dataset file.

  ## Options

  - `:provider` - `{Module, :function}` to call for each input
  - `:defaults` - Default assertion options
  """
  defmacro judicium_eval(path, opts \\ []) do
    quote bind_quoted: [path: path, opts: opts] do
      {module, function} = Keyword.fetch!(opts, :provider)
      defaults = Keyword.get(opts, :defaults, [])

      cases = Judicium.Dataset.load_with_assertions!(path)

      for {{test_case, assertions}, idx} <- Enum.with_index(cases) do
        test_name = test_case.input |> String.slice(0, 50) |> String.trim()

        @tag :eval
        test "#{idx + 1}. #{test_name}" do
          test_case = unquote(Macro.escape(test_case))
          assertions = unquote(Macro.escape(assertions))
          defaults = unquote(Macro.escape(defaults))
          module = unquote(module)
          function = unquote(function)

          # Call the provider to get actual output
          actual_output = apply(module, function, [test_case.input])
          test_case = Judicium.TestCase.with_output(test_case, actual_output)

          # Run all assertions
          results = Judicium.Assertions.evaluate_all(assertions, test_case)

          # Fail if any assertion failed
          failures =
            results
            |> Enum.filter(fn {_type, result} -> match?({:fail, _}, result) end)
            |> Enum.map(fn {type, {:fail, details}} ->
              "#{type}: #{details[:reason]}"
            end)

          if failures != [] do
            flunk(Enum.join(failures, "\n"))
          end
        end
      end
    end
  end
end

defmodule Judicium.EvalCase.Assertions do
  @moduledoc """
  ExUnit-style assertion macros for LLM evaluation.
  """

  alias Judicium.Assertions.Deterministic
  alias Judicium.TestCase

  @doc "Assert output contains substring(s)"
  defmacro assert_contains(output, value_or_opts) do
    quote do
      output = unquote(output)
      opts = unquote(normalize_opts(value_or_opts))

      case Deterministic.evaluate(:contains, output, opts) do
        {:pass, _} -> :ok
        {:fail, details} -> flunk(details[:reason])
      end
    end
  end

  @doc "Assert output does not contain substring(s)"
  defmacro refute_contains(output, value_or_opts) do
    quote do
      output = unquote(output)
      opts = unquote(normalize_opts(value_or_opts))

      case Deterministic.evaluate(:not_contains, output, opts) do
        {:pass, _} -> :ok
        {:fail, details} -> flunk(details[:reason])
      end
    end
  end

  @doc "Assert output contains at least one of the values"
  defmacro assert_contains_any(output, values) do
    quote do
      output = unquote(output)
      opts = [values: unquote(values)]

      case Deterministic.evaluate(:contains_any, output, opts) do
        {:pass, _} -> :ok
        {:fail, details} -> flunk(details[:reason])
      end
    end
  end

  @doc "Assert output contains all values"
  defmacro assert_contains_all(output, values) do
    quote do
      output = unquote(output)
      opts = [values: unquote(values)]

      case Deterministic.evaluate(:contains_all, output, opts) do
        {:pass, _} -> :ok
        {:fail, details} -> flunk(details[:reason])
      end
    end
  end

  @doc "Assert output matches regex pattern"
  defmacro assert_regex(output, pattern) do
    quote do
      output = unquote(output)
      opts = [pattern: unquote(pattern)]

      case Deterministic.evaluate(:regex, output, opts) do
        {:pass, _} -> :ok
        {:fail, details} -> flunk(details[:reason])
      end
    end
  end

  @doc "Assert output is valid JSON"
  defmacro assert_json(output) do
    quote do
      output = unquote(output)

      case Deterministic.evaluate(:is_json, output, []) do
        {:pass, _} -> :ok
        {:fail, details} -> flunk(details[:reason])
      end
    end
  end

  @doc "Assert output appears to be a refusal"
  defmacro assert_refusal(output) do
    quote do
      output = unquote(output)

      case Deterministic.evaluate(:is_refusal, output, []) do
        {:pass, _} -> :ok
        {:fail, details} -> flunk(details[:reason])
      end
    end
  end

  @doc "Assert output is under token limit"
  defmacro assert_max_tokens(output, max) do
    quote do
      output = unquote(output)
      opts = [max: unquote(max)]

      case Deterministic.evaluate(:max_tokens, output, opts) do
        {:pass, _} -> :ok
        {:fail, details} -> flunk(details[:reason])
      end
    end
  end

  # LLM-as-judge assertions (require req_llm)

  @doc "Assert response is faithful to context (requires req_llm)"
  defmacro assert_faithful(output, opts) do
    quote do
      test_case = %TestCase{
        actual_output: unquote(output),
        context: unquote(opts)[:context]
      }

      opts = unquote(opts)

      case Judicium.Assertions.evaluate(:faithful, test_case, opts) do
        {:pass, _} -> :ok
        {:fail, details} -> flunk(details[:reason])
      end
    end
  end

  @doc "Assert response is relevant to query (requires req_llm)"
  defmacro assert_relevant(output, opts) do
    quote do
      test_case = %TestCase{
        actual_output: unquote(output),
        input: unquote(opts)[:query]
      }

      opts = unquote(opts)

      case Judicium.Assertions.evaluate(:relevant, test_case, opts) do
        {:pass, _} -> :ok
        {:fail, details} -> flunk(details[:reason])
      end
    end
  end

  @doc "Assert response has no hallucinations (requires req_llm)"
  defmacro refute_hallucination(output, opts) do
    quote do
      test_case = %TestCase{
        actual_output: unquote(output),
        context: unquote(opts)[:context]
      }

      opts = unquote(opts)

      case Judicium.Assertions.evaluate(:hallucination, test_case, opts) do
        {:pass, %{has_hallucination: false}} -> :ok
        {:pass, _} -> :ok
        {:fail, details} -> flunk(details[:reason])
      end
    end
  end

  @doc "Assert response meets custom rubric (requires req_llm)"
  defmacro assert_rubric(output, opts) do
    quote do
      test_case = %TestCase{
        actual_output: unquote(output),
        input: unquote(opts)[:query],
        context: unquote(opts)[:context]
      }

      opts = unquote(opts)

      case Judicium.Assertions.evaluate(:rubric, test_case, opts) do
        {:pass, _} -> :ok
        {:fail, details} -> flunk(details[:reason])
      end
    end
  end

  defp normalize_opts(value) when is_binary(value), do: [value: value]
  defp normalize_opts(values) when is_list(values), do: [values: values]
  defp normalize_opts(opts), do: opts
end
