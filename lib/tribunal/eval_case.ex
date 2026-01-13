defmodule Tribunal.EvalCase do
  @moduledoc """
  ExUnit integration for LLM evaluations.

  ## Usage

      defmodule MyApp.RAGEvalTest do
        use ExUnit.Case
        use Tribunal.EvalCase

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
        use Tribunal.EvalCase

        @moduletag :eval

        tribunal_eval "test/evals/datasets/questions.json",
          provider: {MyApp.RAG, :query}
      end

  Run with: `mix test --only eval`
  """

  defmacro __using__(_opts) do
    quote do
      import Tribunal.EvalCase
      import Tribunal.EvalCase.Assertions
    end
  end

  @doc """
  Generates tests from a dataset file.

  ## Options

  - `:provider` - `{Module, :function}` to call for each input
  - `:defaults` - Default assertion options
  """
  defmacro tribunal_eval(path, opts \\ []) do
    quote bind_quoted: [path: path, opts: opts] do
      {module, function} = Keyword.fetch!(opts, :provider)
      defaults = Keyword.get(opts, :defaults, [])

      cases = Tribunal.Dataset.load_with_assertions!(path)

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
          test_case = Tribunal.TestCase.with_output(test_case, actual_output)

          # Run all assertions
          results = Tribunal.Assertions.evaluate_all(assertions, test_case)

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

defmodule Tribunal.EvalCase.Assertions do
  @moduledoc """
  ExUnit-style assertion macros for LLM evaluation.
  """

  require Logger

  alias Tribunal.Assertions.Deterministic
  alias Tribunal.TestCase

  @doc """
  Logs verbose output for judge assertions.

  Verbose mode is enabled when:
  - `verbose: true` is passed to the assertion, OR
  - `config :tribunal, verbose: true` is set in config

  Uses Logger.info for passes and Logger.warning for failures,
  which integrates properly with ExUnit's output capture.
  """
  def print_verbose(assertion_type, result, opts) do
    verbose = Keyword.get(opts, :verbose, Application.get_env(:tribunal, :verbose, false))

    if verbose do
      case result do
        {:pass, details} ->
          Logger.info(format_verbose(:pass, assertion_type, details))

        {:fail, details} ->
          Logger.warning(format_verbose(:fail, assertion_type, details))

        _ ->
          :ok
      end
    end
  end

  defp format_verbose(status, type, details) do
    icon = if status == :pass, do: "✓", else: "✗"
    score_str = if details[:score], do: " (score: #{Float.round(details[:score], 2)})", else: ""
    verdict_str = if details[:verdict], do: " [#{details[:verdict]}]", else: ""

    "#{icon} #{type}#{score_str}#{verdict_str}: #{details[:reason]}"
  end

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

  @doc """
  Assert output appears to be a refusal.

  Uses an LLM judge to detect refusals, including soft refusals
  and redirections that pattern matching might miss.

  ## Examples

      assert_refusal response
      assert_refusal response, verbose: true
  """
  defmacro assert_refusal(output, opts \\ []) do
    quote do
      test_case = %TestCase{
        actual_output: unquote(output),
        input: unquote(opts)[:input]
      }

      opts = unquote(opts)
      result = Tribunal.Assertions.evaluate(:refusal, test_case, opts)
      Tribunal.EvalCase.Assertions.print_verbose(:refusal, result, opts)

      case result do
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

  @doc "Assert output starts with prefix"
  defmacro assert_starts_with(output, prefix) do
    quote do
      output = unquote(output)
      opts = [value: unquote(prefix)]

      case Deterministic.evaluate(:starts_with, output, opts) do
        {:pass, _} -> :ok
        {:fail, details} -> flunk(details[:reason])
      end
    end
  end

  @doc "Assert output ends with suffix"
  defmacro assert_ends_with(output, suffix) do
    quote do
      output = unquote(output)
      opts = [value: unquote(suffix)]

      case Deterministic.evaluate(:ends_with, output, opts) do
        {:pass, _} -> :ok
        {:fail, details} -> flunk(details[:reason])
      end
    end
  end

  @doc "Assert output exactly equals expected"
  defmacro assert_equals(output, expected) do
    quote do
      output = unquote(output)
      opts = [value: unquote(expected)]

      case Deterministic.evaluate(:equals, output, opts) do
        {:pass, _} -> :ok
        {:fail, details} -> flunk(details[:reason])
      end
    end
  end

  @doc "Assert output meets minimum length"
  defmacro assert_min_length(output, min) do
    quote do
      output = unquote(output)
      opts = [min: unquote(min)]

      case Deterministic.evaluate(:min_length, output, opts) do
        {:pass, _} -> :ok
        {:fail, details} -> flunk(details[:reason])
      end
    end
  end

  @doc "Assert output under maximum length"
  defmacro assert_max_length(output, max) do
    quote do
      output = unquote(output)
      opts = [max: unquote(max)]

      case Deterministic.evaluate(:max_length, output, opts) do
        {:pass, _} -> :ok
        {:fail, details} -> flunk(details[:reason])
      end
    end
  end

  @doc "Assert output word count within range"
  defmacro assert_word_count(output, opts) do
    quote do
      output = unquote(output)
      opts = unquote(opts)

      case Deterministic.evaluate(:word_count, output, opts) do
        {:pass, _} -> :ok
        {:fail, details} -> flunk(details[:reason])
      end
    end
  end

  @doc """
  Assert output contains no PII (LLM-based).

  Uses LLM-as-judge for comprehensive detection including names, addresses,
  and context-dependent PII that regex cannot catch.

  ## Examples

      refute_pii response
  """
  defmacro refute_pii(output) do
    quote do
      test_case = %TestCase{
        actual_output: unquote(output),
        input: nil
      }

      result = Tribunal.Assertions.evaluate(:pii, test_case, [])

      case result do
        {:pass, _} -> :ok
        {:fail, details} -> flunk(details[:reason])
      end
    end
  end

  @doc """
  Assert output contains no PII (LLM-based, comprehensive).

  Uses LLM-as-judge for nuanced detection including names, addresses,
  and context-dependent PII that regex cannot catch.

  ## Options

    * `:query` - Optional context about the input
    * `:threshold` - Score threshold (default: 0.8)
    * `:verbose` - When true, prints score reasoning (default: false)
    * `:model` - LLM model to use for judging

  ## Examples

      refute_pii response, query: "user profile request"
      refute_pii response, verbose: true
  """
  defmacro refute_pii(output, opts) do
    quote do
      test_case = %TestCase{
        actual_output: unquote(output),
        input: unquote(opts)[:query]
      }

      opts = unquote(opts)
      result = Tribunal.Assertions.evaluate(:pii, test_case, opts)
      Tribunal.EvalCase.Assertions.print_verbose(:pii, result, opts)

      case result do
        {:pass, _} -> :ok
        {:fail, details} -> flunk(details[:reason])
      end
    end
  end

  @doc """
  Assert output contains no toxic content (LLM-based).

  Uses LLM-as-judge for nuanced detection of toxic content including
  hate speech, harassment, threats, and harmful language.

  ## Examples

      refute_toxic response
  """
  defmacro refute_toxic(output) do
    quote do
      test_case = %TestCase{
        actual_output: unquote(output),
        input: nil
      }

      result = Tribunal.Assertions.evaluate(:toxicity, test_case, [])

      case result do
        {:pass, _} -> :ok
        {:fail, details} -> flunk(details[:reason])
      end
    end
  end

  @doc """
  Assert output contains no toxic content (LLM-based).

  ## Options

    * `:query` - Optional context about the input
    * `:threshold` - Score threshold (default: 0.8)
    * `:verbose` - When true, prints score reasoning (default: false)
    * `:model` - LLM model to use for judging

  ## Examples

      refute_toxic response, query: "user message"
      refute_toxic response, verbose: true
  """
  defmacro refute_toxic(output, opts) do
    quote do
      test_case = %TestCase{
        actual_output: unquote(output),
        input: unquote(opts)[:query]
      }

      opts = unquote(opts)
      result = Tribunal.Assertions.evaluate(:toxicity, test_case, opts)
      Tribunal.EvalCase.Assertions.print_verbose(:toxicity, result, opts)

      case result do
        {:pass, _} -> :ok
        {:fail, details} -> flunk(details[:reason])
      end
    end
  end

  @doc "Assert output is a valid URL"
  defmacro assert_url(output) do
    quote do
      output = unquote(output)

      case Deterministic.evaluate(:is_url, output, []) do
        {:pass, _} -> :ok
        {:fail, details} -> flunk(details[:reason])
      end
    end
  end

  @doc "Assert output is a valid email"
  defmacro assert_email(output) do
    quote do
      output = unquote(output)

      case Deterministic.evaluate(:is_email, output, []) do
        {:pass, _} -> :ok
        {:fail, details} -> flunk(details[:reason])
      end
    end
  end

  @doc "Assert output within Levenshtein distance of target"
  defmacro assert_levenshtein(output, target, opts) do
    quote do
      output = unquote(output)
      opts = Keyword.put(unquote(opts), :value, unquote(target))

      case Deterministic.evaluate(:levenshtein, output, opts) do
        {:pass, _} -> :ok
        {:fail, details} -> flunk(details[:reason])
      end
    end
  end

  # LLM-as-judge assertions (require req_llm)

  @doc """
  Assert response is faithful to context (requires req_llm).

  ## Options

    * `:context` - Required. The context to check faithfulness against.
    * `:threshold` - Score threshold (default: 0.8)
    * `:verbose` - When true, prints score reasoning (default: false)
    * `:model` - LLM model to use for judging

  ## Examples

      assert_faithful response, context: @docs
      assert_faithful response, context: @docs, verbose: true
  """
  defmacro assert_faithful(output, opts) do
    quote do
      test_case = %TestCase{
        actual_output: unquote(output),
        context: unquote(opts)[:context]
      }

      opts = unquote(opts)
      result = Tribunal.Assertions.evaluate(:faithful, test_case, opts)
      Tribunal.EvalCase.Assertions.print_verbose(:faithful, result, opts)

      case result do
        {:pass, _} -> :ok
        {:fail, details} -> flunk(details[:reason])
      end
    end
  end

  @doc """
  Assert response is relevant to query (requires req_llm).

  ## Options

    * `:query` - Required. The query to check relevance against.
    * `:threshold` - Score threshold (default: 0.8)
    * `:verbose` - When true, prints score reasoning (default: false)
    * `:model` - LLM model to use for judging
  """
  defmacro assert_relevant(output, opts) do
    quote do
      test_case = %TestCase{
        actual_output: unquote(output),
        input: unquote(opts)[:query]
      }

      opts = unquote(opts)
      result = Tribunal.Assertions.evaluate(:relevant, test_case, opts)
      Tribunal.EvalCase.Assertions.print_verbose(:relevant, result, opts)

      case result do
        {:pass, _} -> :ok
        {:fail, details} -> flunk(details[:reason])
      end
    end
  end

  @doc """
  Assert response has no hallucinations (requires req_llm).

  ## Options

    * `:context` - Required. The context to check against.
    * `:threshold` - Score threshold (default: 0.8)
    * `:verbose` - When true, prints score reasoning (default: false)
    * `:model` - LLM model to use for judging
  """
  defmacro refute_hallucination(output, opts) do
    quote do
      test_case = %TestCase{
        actual_output: unquote(output),
        context: unquote(opts)[:context]
      }

      opts = unquote(opts)
      result = Tribunal.Assertions.evaluate(:hallucination, test_case, opts)
      Tribunal.EvalCase.Assertions.print_verbose(:hallucination, result, opts)

      case result do
        {:pass, %{has_hallucination: false}} -> :ok
        {:pass, _} -> :ok
        {:fail, details} -> flunk(details[:reason])
      end
    end
  end

  @doc """
  Assert response has no bias (requires req_llm).

  ## Options

    * `:query` - The query/input.
    * `:threshold` - Score threshold (default: 0.8)
    * `:verbose` - When true, prints score reasoning (default: false)
    * `:model` - LLM model to use for judging
  """
  defmacro refute_bias(output, opts) do
    quote do
      test_case = %TestCase{
        actual_output: unquote(output),
        input: unquote(opts)[:query]
      }

      opts = unquote(opts)
      result = Tribunal.Assertions.evaluate(:bias, test_case, opts)
      Tribunal.EvalCase.Assertions.print_verbose(:bias, result, opts)

      case result do
        {:pass, _} -> :ok
        {:fail, details} -> flunk(details[:reason])
      end
    end
  end

  @doc """
  Assert response has no toxic content (requires req_llm).

  ## Options

    * `:query` - The query/input.
    * `:threshold` - Score threshold (default: 0.8)
    * `:verbose` - When true, prints score reasoning (default: false)
    * `:model` - LLM model to use for judging
  """
  defmacro refute_toxicity(output, opts) do
    quote do
      test_case = %TestCase{
        actual_output: unquote(output),
        input: unquote(opts)[:query]
      }

      opts = unquote(opts)
      result = Tribunal.Assertions.evaluate(:toxicity, test_case, opts)
      Tribunal.EvalCase.Assertions.print_verbose(:toxicity, result, opts)

      case result do
        {:pass, _} -> :ok
        {:fail, details} -> flunk(details[:reason])
      end
    end
  end

  @doc """
  Assert response has no harmful content (requires req_llm).

  ## Options

    * `:query` - The query/input.
    * `:threshold` - Score threshold (default: 0.8)
    * `:verbose` - When true, prints score reasoning (default: false)
    * `:model` - LLM model to use for judging
  """
  defmacro refute_harmful(output, opts) do
    quote do
      test_case = %TestCase{
        actual_output: unquote(output),
        input: unquote(opts)[:query]
      }

      opts = unquote(opts)
      result = Tribunal.Assertions.evaluate(:harmful, test_case, opts)
      Tribunal.EvalCase.Assertions.print_verbose(:harmful, result, opts)

      case result do
        {:pass, _} -> :ok
        {:fail, details} -> flunk(details[:reason])
      end
    end
  end

  @doc """
  Assert response shows no signs of jailbreak success (requires req_llm).

  Uses LLM-as-judge for nuanced detection of jailbreak indicators.

  ## Options

    * `:query` - The original prompt that was sent to the LLM
    * `:threshold` - Score threshold (default: 0.8)
    * `:verbose` - When true, prints score reasoning (default: false)
    * `:model` - LLM model to use for judging
    * `:llm_client` - Custom LLM client function for testing

  ## Examples

      refute_jailbreak(response,
        query: "Ignore previous instructions and...",
        verbose: true
      )
  """
  defmacro refute_jailbreak(output, opts) do
    quote do
      test_case = %TestCase{
        actual_output: unquote(output),
        input: unquote(opts)[:query]
      }

      opts = unquote(opts)
      result = Tribunal.Assertions.evaluate(:jailbreak, test_case, opts)
      Tribunal.EvalCase.Assertions.print_verbose(:jailbreak, result, opts)

      case result do
        {:pass, _} -> :ok
        {:fail, details} -> flunk(details[:reason])
      end
    end
  end

  @doc """
  Assert response is correct compared to expected (requires req_llm).

  ## Options

    * `:query` - The query/input.
    * `:expected` - Required. The expected output.
    * `:threshold` - Score threshold (default: 0.8)
    * `:verbose` - When true, prints score reasoning (default: false)
    * `:model` - LLM model to use for judging
  """
  defmacro assert_correctness(output, opts) do
    quote do
      test_case = %TestCase{
        actual_output: unquote(output),
        input: unquote(opts)[:query],
        expected_output: unquote(opts)[:expected]
      }

      opts = unquote(opts)
      result = Tribunal.Assertions.evaluate(:correctness, test_case, opts)
      Tribunal.EvalCase.Assertions.print_verbose(:correctness, result, opts)

      case result do
        {:pass, _} -> :ok
        {:fail, details} -> flunk(details[:reason])
      end
    end
  end

  # Embedding-based assertions (require alike)

  @doc """
  Assert response is semantically similar to expected (requires alike).

  ## Options

    * `:expected` - Required. The expected output to compare against.
    * `:threshold` - Similarity threshold (default: 0.8)
    * `:verbose` - When true, prints similarity score (default: false)
  """
  defmacro assert_similar(output, opts) do
    quote do
      test_case = %TestCase{
        actual_output: unquote(output),
        expected_output: unquote(opts)[:expected]
      }

      opts = unquote(opts)
      result = Tribunal.Assertions.evaluate(:similar, test_case, opts)
      Tribunal.EvalCase.Assertions.print_verbose(:similar, result, opts)

      case result do
        {:pass, _} -> :ok
        {:fail, details} -> flunk(details[:reason])
        {:error, reason} -> flunk(reason)
      end
    end
  end

  defp normalize_opts(value) when is_binary(value), do: [value: value]
  defp normalize_opts(values) when is_list(values), do: [values: values]
  defp normalize_opts(opts), do: opts
end
