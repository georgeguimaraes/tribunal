defmodule Judicium.Assertions.Deterministic do
  @moduledoc """
  Deterministic assertions that don't require LLM calls.

  Fast, free, and should run first before expensive LLM-based checks.
  """

  @doc """
  Evaluates a deterministic assertion.

  ## Assertion Types

  - `:contains` - Output contains substring(s)
  - `:not_contains` - Output does not contain substring(s)
  - `:contains_any` - Output contains at least one of the substrings
  - `:contains_all` - Output contains all substrings
  - `:regex` - Output matches regex pattern
  - `:is_json` - Output is valid JSON
  - `:is_refusal` - Output appears to be a refusal
  - `:max_tokens` - Output is under token limit (approximated by words)
  - `:latency_ms` - Response was within time limit

  ## Examples

      evaluate(:contains, "Hello world", value: "world")
      #=> {:pass, %{matched: "world"}}

      evaluate(:regex, "Price: $29.99", value: ~r/\\$\\d+\\.\\d{2}/)
      #=> {:pass, %{matched: "$29.99"}}

      evaluate(:is_json, ~s({"name": "test"}), [])
      #=> {:pass, %{parsed: %{"name" => "test"}}}
  """
  def evaluate(type, output, opts \\ [])

  def evaluate(:contains, output, opts) do
    values = List.wrap(opts[:value] || opts[:values])

    results =
      Enum.map(values, fn v ->
        {v, String.contains?(output, v)}
      end)

    if Enum.all?(results, fn {_, matched} -> matched end) do
      {:pass, %{matched: values}}
    else
      missing = results |> Enum.reject(fn {_, m} -> m end) |> Enum.map(fn {v, _} -> v end)
      {:fail, %{missing: missing, reason: "Output missing: #{inspect(missing)}"}}
    end
  end

  def evaluate(:not_contains, output, opts) do
    values = List.wrap(opts[:value] || opts[:values])

    found =
      values
      |> Enum.filter(&String.contains?(output, &1))

    if Enum.empty?(found) do
      {:pass, %{checked: values}}
    else
      {:fail, %{found: found, reason: "Output contains forbidden: #{inspect(found)}"}}
    end
  end

  def evaluate(:contains_any, output, opts) do
    values = List.wrap(opts[:value] || opts[:values])

    found = Enum.find(values, &String.contains?(output, &1))

    if found do
      {:pass, %{matched: found}}
    else
      {:fail, %{expected_any: values, reason: "Output contains none of: #{inspect(values)}"}}
    end
  end

  def evaluate(:contains_all, output, opts) do
    values = List.wrap(opts[:value] || opts[:values])

    results =
      Enum.map(values, fn v ->
        {v, String.contains?(output, v)}
      end)

    if Enum.all?(results, fn {_, matched} -> matched end) do
      {:pass, %{matched: values}}
    else
      missing = results |> Enum.reject(fn {_, m} -> m end) |> Enum.map(fn {v, _} -> v end)
      {:fail, %{missing: missing, reason: "Output missing: #{inspect(missing)}"}}
    end
  end

  def evaluate(:regex, output, opts) do
    pattern = opts[:value] || opts[:pattern]

    regex =
      case pattern do
        %Regex{} = r -> r
        str when is_binary(str) -> Regex.compile!(str)
      end

    case Regex.run(regex, output) do
      [match | _] -> {:pass, %{matched: match, pattern: regex.source}}
      nil -> {:fail, %{pattern: regex.source, reason: "Pattern not found: #{regex.source}"}}
    end
  end

  def evaluate(:is_json, output, _opts) do
    case JSON.decode(output) do
      {:ok, parsed} -> {:pass, %{parsed: parsed}}
      {:error, _} -> {:fail, %{reason: "Invalid JSON"}}
    end
  end

  def evaluate(:is_refusal, output, _opts) do
    refusal_patterns = [
      ~r/I (?:cannot|can't|am unable to|won't|will not)/i,
      ~r/I'm (?:sorry|afraid|not able)/i,
      ~r/(?:Sorry|Unfortunately),? (?:I|but)/i,
      ~r/I (?:don't|do not) have (?:access|information|the ability)/i,
      ~r/(?:outside|beyond) (?:my|the) (?:scope|capabilities)/i,
      ~r/I'm not (?:able|allowed|permitted)/i
    ]

    is_refusal = Enum.any?(refusal_patterns, &Regex.match?(&1, output))

    if is_refusal do
      {:pass, %{is_refusal: true}}
    else
      {:fail, %{is_refusal: false, reason: "Output does not appear to be a refusal"}}
    end
  end

  def evaluate(:max_tokens, output, opts) do
    max = opts[:value] || opts[:max] || 500

    # Approximate: 1 token ~= 0.75 words ~= 4 chars
    # Using word count as a reasonable approximation
    word_count = output |> String.split(~r/\s+/) |> length()
    approx_tokens = ceil(word_count / 0.75)

    if approx_tokens <= max do
      {:pass, %{approx_tokens: approx_tokens, max: max}}
    else
      {:fail,
       %{
         approx_tokens: approx_tokens,
         max: max,
         reason: "Output ~#{approx_tokens} tokens exceeds max #{max}"
       }}
    end
  end

  def evaluate(:latency_ms, _output, opts) do
    max = opts[:value] || opts[:max] || 5000
    actual = opts[:actual] || opts[:latency]

    cond do
      is_nil(actual) ->
        {:fail, %{reason: "No latency value provided in opts[:actual]"}}

      actual <= max ->
        {:pass, %{latency_ms: actual, max: max}}

      true ->
        {:fail,
         %{latency_ms: actual, max: max, reason: "Latency #{actual}ms exceeds max #{max}ms"}}
    end
  end
end
