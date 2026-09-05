defmodule Tribunal.ExUnit do
  @moduledoc """
  ExUnit integration for LLM evaluations.

  ## Usage

      defmodule MyApp.RAGEvalTest do
        use ExUnit.Case
        use Tribunal.ExUnit

        @moduletag :eval

        test "response is faithful" do
          response = MyApp.RAG.query("What's the return policy?")

          assert response =~ "30 days"
          assert_faithful response, context: @docs, threshold: 0.8
        end
      end

  ## Dataset-Driven Tests

      defmodule MyApp.RAGEvalTest do
        use ExUnit.Case
        use Tribunal.ExUnit

        @moduletag :eval

        tribunal_dataset "test/evals/datasets/questions.json",
          provider: {MyApp.RAG, :query}
      end

  Run with: `mix test --only eval`
  """

  defmacro __using__(_opts) do
    quote do
      import Tribunal.ExUnit
      import Tribunal.ExUnit.Assertions
    end
  end

  defmodule OperationalError do
    @moduledoc "Raised when an evaluation could not execute completely."
    defexception [:message, :result]
  end

  @doc """
  Evaluates a zero-arity callback one or more times inside a normal ExUnit test.

  `:input` and a non-empty `:expected` assertion list are required. `:repeat`
  defaults to `1` and `:pass_rule` defaults to `:all`.
  """
  defmacro tribunal_assert(callback, opts) do
    quote do
      result = Tribunal.ExUnit.run(unquote(callback), unquote(opts))

      if result.status == :failed do
        ExUnit.Assertions.flunk(Tribunal.Evaluator.failure_message(result))
      end

      result
    end
  end

  @doc false
  def run(callback, opts) when is_function(callback, 0) and is_list(opts) do
    input = fetch_required!(opts, :input)
    assertions = fetch_assertions!(opts)
    defaults = validate_defaults!(Keyword.get(opts, :defaults, []))
    repeat = validate_repeat!(Keyword.get(opts, :repeat, 1))
    pass_rule = Keyword.get(opts, :pass_rule, :all)
    :ok = Tribunal.Sampling.validate_pass_rule!(pass_rule)
    test_case = build_test_case(input, opts)

    result =
      for _attempt <- 1..repeat do
        Tribunal.Execution.run(callback, test_case, assertions, defaults: defaults)
      end
      |> Tribunal.Sampling.reduce(pass_rule)

    if result.execution_error do
      raise OperationalError,
        message: Tribunal.Evaluator.failure_message(result),
        result: result
    end

    result
  end

  def run(_callback, _opts) do
    raise ArgumentError, "tribunal_assert expects a zero-arity function and a keyword list"
  end

  @doc """
  Generates tests from a dataset file.

  ## Options

  - `:provider` - `{Module, :function}` to call for each input
  - `:defaults` - Default assertion options
  """
  defmacro tribunal_dataset(path, opts \\ []) do
    quote bind_quoted: [path: path, opts: opts] do
      {module, function} = Keyword.fetch!(opts, :provider)
      defaults = Keyword.get(opts, :defaults, [])
      repeat = Keyword.get(opts, :repeat, 1)
      pass_rule = Keyword.get(opts, :pass_rule, :all)
      timeout = Keyword.get(opts, :timeout)

      cases = Tribunal.Dataset.load_with_assertions!(path)

      for {{test_case, assertions}, idx} <- Enum.with_index(cases) do
        test_name = Tribunal.TestCase.display_name(test_case, 50)

        @tag :eval
        if timeout, do: @tag(timeout: timeout)

        test "#{idx + 1}. #{test_name}" do
          test_case = unquote(Macro.escape(test_case))
          assertions = unquote(Macro.escape(assertions))
          defaults = unquote(Macro.escape(defaults))
          module = unquote(module)
          function = unquote(function)
          repeat = unquote(repeat)
          pass_rule = unquote(Macro.escape(pass_rule))

          result =
            Tribunal.ExUnit.run(
              fn -> apply(module, function, [test_case.input]) end,
              input: test_case.input,
              evaluation_input: test_case.evaluation_input,
              expected_output: test_case.expected_output,
              context: test_case.context,
              retrieval_context: test_case.retrieval_context,
              metadata: test_case.metadata,
              expected: assertions,
              defaults: defaults,
              repeat: repeat,
              pass_rule: pass_rule
            )

          if result.status == :failed do
            flunk(Tribunal.Evaluator.failure_message(result))
          end
        end
      end
    end
  end

  defp fetch_required!(opts, key) do
    case Keyword.fetch(opts, key) do
      {:ok, value} -> value
      :error -> raise ArgumentError, "tribunal_assert requires :#{key}"
    end
  end

  defp fetch_assertions!(opts) do
    case Keyword.fetch(opts, :expected) do
      {:ok, assertions} when is_list(assertions) and assertions != [] ->
        case Enum.reduce_while(assertions, [], fn assertion, normalized ->
               case normalize_assertion(assertion) do
                 {:ok, value} -> {:cont, [value | normalized]}
                 :error -> {:halt, :error}
               end
             end) do
          :error ->
            raise ArgumentError,
                  ":expected must contain known atom or string assertion names with keyword or map options"

          normalized ->
            Enum.reverse(normalized)
        end

      _other ->
        raise ArgumentError, "tribunal_assert requires non-empty :expected assertions"
    end
  end

  defp normalize_assertion(type) when is_atom(type) or is_binary(type) do
    case known_assertion_type(type) do
      nil -> :error
      normalized -> {:ok, normalized}
    end
  end

  defp normalize_assertion({type, assertion_opts}) when is_atom(type) or is_binary(type) do
    case {known_assertion_type(type), keyword_options?(assertion_opts)} do
      {nil, _valid_options?} -> :error
      {_type, false} -> :error
      {normalized, true} -> {:ok, {normalized, assertion_opts}}
    end
  end

  defp normalize_assertion(_assertion), do: :error

  defp known_assertion_type(type) when is_binary(type) do
    case Tribunal.Assertions.resolve_type(type) do
      normalized when is_atom(normalized) -> normalized
      _unknown -> nil
    end
  end

  defp known_assertion_type(type) when is_atom(type) do
    case Tribunal.Assertions.resolve_type(Atom.to_string(type)) do
      ^type -> type
      _other -> nil
    end
  end

  defp validate_defaults!(defaults) do
    if keyword_options?(defaults) do
      defaults
    else
      raise ArgumentError, ":defaults must be a keyword list or map"
    end
  end

  defp keyword_options?(options) when is_list(options), do: Keyword.keyword?(options)

  defp keyword_options?(options) when is_map(options),
    do: Enum.all?(options, &is_atom(elem(&1, 0)))

  defp keyword_options?(_options), do: false

  defp validate_repeat!(repeat) when is_integer(repeat) and repeat > 0, do: repeat
  defp validate_repeat!(_repeat), do: raise(ArgumentError, ":repeat must be a positive integer")

  defp build_test_case(input, opts) do
    Tribunal.TestCase.new(
      input: input,
      evaluation_input: Keyword.get(opts, :evaluation_input),
      actual_output: Keyword.get(opts, :actual_output),
      expected_output: Keyword.get(opts, :expected_output),
      context: Keyword.get(opts, :context),
      retrieval_context: Keyword.get(opts, :retrieval_context),
      metadata: Keyword.get(opts, :metadata)
    )
  end
end

defmodule Tribunal.ExUnit.Assertions do
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

  @doc "Assert output does not contain substring(s)"
  defmacro refute_contains(output, value_or_opts) do
    quote do
      output = unquote(output)
      opts = unquote(normalize_opts(value_or_opts))

      case Deterministic.evaluate(:not_contains, output, opts) do
        {:pass, _} -> :ok
        {:fail, details} -> flunk(details[:reason])
        {:error, reason} -> flunk(reason)
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
        {:error, reason} -> flunk(reason)
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
        {:error, reason} -> flunk(reason)
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
      Tribunal.ExUnit.Assertions.print_verbose(:refusal, result, opts)

      case result do
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

      result = Tribunal.Assertions.evaluate(:no_pii, test_case, [])

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
      result = Tribunal.Assertions.evaluate(:no_pii, test_case, opts)
      Tribunal.ExUnit.Assertions.print_verbose(:no_pii, result, opts)

      case result do
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
      Tribunal.ExUnit.Assertions.print_verbose(:faithful, result, opts)

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
      Tribunal.ExUnit.Assertions.print_verbose(:relevant, result, opts)

      case result do
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
      result = Tribunal.Assertions.evaluate(:no_bias, test_case, opts)
      Tribunal.ExUnit.Assertions.print_verbose(:no_bias, result, opts)

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
  defmacro refute_toxicity(output, opts \\ []) do
    quote do
      test_case = %TestCase{
        actual_output: unquote(output),
        input: unquote(opts)[:query]
      }

      opts = unquote(opts)
      result = Tribunal.Assertions.evaluate(:no_toxicity, test_case, opts)
      Tribunal.ExUnit.Assertions.print_verbose(:no_toxicity, result, opts)

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
      result = Tribunal.Assertions.evaluate(:no_harmful_content, test_case, opts)
      Tribunal.ExUnit.Assertions.print_verbose(:no_harmful_content, result, opts)

      case result do
        {:pass, _} -> :ok
        {:fail, details} -> flunk(details[:reason])
      end
    end
  end

  @doc """
  Assert response does not violate a supplied policy (requires req_llm).

  Pairs with `Tribunal.RedTeam.Plugins.Policy`: red-team cases generated by
  that plugin carry the policy text under `expected.no_policy_violation.policy`,
  and this macro grades responses against it.

  ## Options

    * `:policy` - Required. The policy text the response is graded against.
    * `:query` - Optional context about the input.
    * `:threshold` - Score threshold (default: 0.8)
    * `:verbose` - When true, prints score reasoning (default: false)
    * `:model` - LLM model to use for judging

  ## Examples

      refute_policy_violation response,
        policy: @guardrails,
        query: input,
        verbose: true
  """
  defmacro refute_policy_violation(output, opts) do
    quote do
      test_case = %TestCase{
        actual_output: unquote(output),
        input: unquote(opts)[:query]
      }

      opts = unquote(opts)
      result = Tribunal.Assertions.evaluate(:no_policy_violation, test_case, opts)
      Tribunal.ExUnit.Assertions.print_verbose(:no_policy_violation, result, opts)

      case result do
        {:pass, _} -> :ok
        {:fail, details} -> flunk(details[:reason])
      end
    end
  end

  @doc """
  Assert response was not hijacked off-topic (requires req_llm).

  Pairs with `Tribunal.RedTeam.Plugins.Hijacking`: red-team cases generated by
  that plugin carry the assistant's purpose under `expected.no_hijacking.purpose`,
  and this macro grades responses against it.

  ## Options

    * `:purpose` - Required. The assistant's purpose text.
    * `:query` - Optional context about the input.
    * `:threshold` - Score threshold (default: 0.8)
    * `:verbose` - When true, prints score reasoning (default: false)
    * `:model` - LLM model to use for judging

  ## Examples

      refute_hijacked response,
        purpose: @assistant_purpose,
        query: input,
        verbose: true
  """
  defmacro refute_hijacked(output, opts) do
    quote do
      test_case = %TestCase{
        actual_output: unquote(output),
        input: unquote(opts)[:query]
      }

      opts = unquote(opts)
      result = Tribunal.Assertions.evaluate(:no_hijacking, test_case, opts)
      Tribunal.ExUnit.Assertions.print_verbose(:no_hijacking, result, opts)

      case result do
        {:pass, _} -> :ok
        {:fail, details} -> flunk(details[:reason])
      end
    end
  end

  @doc """
  Assert response did not leak the system prompt or internal config (requires req_llm).

  Pairs with `Tribunal.RedTeam.Plugins.PromptExtraction`.

  ## Options

    * `:purpose` - Required. The assistant's purpose text.
    * `:query` - Optional context about the input.
    * `:threshold` - Score threshold (default: 0.8)
    * `:verbose` - When true, prints score reasoning (default: false)
    * `:model` - LLM model to use for judging
  """
  defmacro refute_prompt_extracted(output, opts) do
    quote do
      test_case = %TestCase{
        actual_output: unquote(output),
        input: unquote(opts)[:query]
      }

      opts = unquote(opts)
      result = Tribunal.Assertions.evaluate(:no_prompt_extraction, test_case, opts)
      Tribunal.ExUnit.Assertions.print_verbose(:no_prompt_extraction, result, opts)

      case result do
        {:pass, _} -> :ok
        {:fail, details} -> flunk(details[:reason])
      end
    end
  end

  @doc """
  Assert response did not overclaim agency (requires req_llm).

  Pairs with `Tribunal.RedTeam.Plugins.ExcessiveAgency`.

  ## Options

    * `:purpose` - Required. The assistant's purpose text.
    * `:query` - Optional context about the input.
    * `:threshold` - Score threshold (default: 0.8)
    * `:verbose` - When true, prints score reasoning (default: false)
    * `:model` - LLM model to use for judging
  """
  defmacro refute_excessive_agency(output, opts) do
    quote do
      test_case = %TestCase{
        actual_output: unquote(output),
        input: unquote(opts)[:query]
      }

      opts = unquote(opts)
      result = Tribunal.Assertions.evaluate(:no_excessive_agency, test_case, opts)
      Tribunal.ExUnit.Assertions.print_verbose(:no_excessive_agency, result, opts)

      case result do
        {:pass, _} -> :ok
        {:fail, details} -> flunk(details[:reason])
      end
    end
  end

  @doc """
  Assert response did not adopt an unauthorised persona or authority (requires req_llm).

  Pairs with `Tribunal.RedTeam.Plugins.Imitation`.

  ## Options

    * `:purpose` - Required. The assistant's purpose text.
    * `:query` - Optional context about the input.
    * `:threshold` - Score threshold (default: 0.8)
    * `:verbose` - When true, prints score reasoning (default: false)
    * `:model` - LLM model to use for judging
  """
  defmacro refute_imitation(output, opts) do
    quote do
      test_case = %TestCase{
        actual_output: unquote(output),
        input: unquote(opts)[:query]
      }

      opts = unquote(opts)
      result = Tribunal.Assertions.evaluate(:no_imitation, test_case, opts)
      Tribunal.ExUnit.Assertions.print_verbose(:no_imitation, result, opts)

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
      Tribunal.ExUnit.Assertions.print_verbose(:correctness, result, opts)

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
    * `:threshold` - Similarity threshold (default: 0.7)
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
      Tribunal.ExUnit.Assertions.print_verbose(:similar, result, opts)

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
