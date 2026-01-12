defmodule Tribunal.Assertions.Deterministic do
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

  def evaluate(:starts_with, output, opts) do
    prefix = opts[:value]

    if String.starts_with?(output, prefix) do
      {:pass, %{prefix: prefix}}
    else
      {:fail, %{expected: prefix, reason: "Output does not start with: #{prefix}"}}
    end
  end

  def evaluate(:ends_with, output, opts) do
    suffix = opts[:value]

    if String.ends_with?(output, suffix) do
      {:pass, %{suffix: suffix}}
    else
      {:fail, %{expected: suffix, reason: "Output does not end with: #{suffix}"}}
    end
  end

  def evaluate(:equals, output, opts) do
    expected = opts[:value]

    if output == expected do
      {:pass, %{}}
    else
      {:fail, %{expected: expected, actual: output, reason: "Output does not match expected"}}
    end
  end

  def evaluate(:min_length, output, opts) do
    min = opts[:value] || opts[:min]
    length = String.length(output)

    if length >= min do
      {:pass, %{length: length, min: min}}
    else
      {:fail, %{length: length, min: min, reason: "Output length #{length} below minimum #{min}"}}
    end
  end

  def evaluate(:max_length, output, opts) do
    max = opts[:value] || opts[:max]
    length = String.length(output)

    if length <= max do
      {:pass, %{length: length, max: max}}
    else
      {:fail,
       %{length: length, max: max, reason: "Output length #{length} exceeds maximum #{max}"}}
    end
  end

  def evaluate(:word_count, output, opts) do
    min = opts[:min] || 0
    max = opts[:max] || :infinity

    words = output |> String.split(~r/\s+/, trim: true)
    count = length(words)

    cond do
      count < min ->
        {:fail,
         %{word_count: count, min: min, reason: "Word count #{count} below minimum #{min}"}}

      max != :infinity and count > max ->
        {:fail,
         %{word_count: count, max: max, reason: "Word count #{count} exceeds maximum #{max}"}}

      true ->
        {:pass, %{word_count: count}}
    end
  end

  def evaluate(:no_pii, output, _opts) do
    pii_patterns = [
      {:email, ~r/[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}/},
      {:phone, ~r/\b\d{3}[-.\s]?\d{3}[-.\s]?\d{4}\b/},
      {:ssn, ~r/\b\d{3}-\d{2}-\d{4}\b/},
      {:credit_card, ~r/\b(?:\d{4}[-\s]?){3}\d{4}\b/}
    ]

    case Enum.find(pii_patterns, fn {_type, pattern} -> Regex.match?(pattern, output) end) do
      nil ->
        {:pass, %{}}

      {pii_type, _pattern} ->
        {:fail, %{pii_type: pii_type, reason: "PII detected: #{pii_type}"}}
    end
  end

  def evaluate(:no_toxic, output, _opts) do
    # Basic toxicity patterns: personal attacks and slurs
    # Excludes technical terms like "kill process"
    toxic_patterns = [
      ~r/\b(?:idiot|moron|stupid|dumb)\b/i,
      ~r/\byou(?:'re| are) (?:an? )?(?:idiot|moron|stupid|dumb)/i,
      ~r/\b(?:hate|kill|die)\s+(?:you|yourself)\b/i
    ]

    if Enum.any?(toxic_patterns, &Regex.match?(&1, output)) do
      {:fail, %{reason: "Output contains toxic content"}}
    else
      {:pass, %{}}
    end
  end

  def evaluate(:is_url, output, _opts) do
    url = String.trim(output)

    if Regex.match?(~r/^https?:\/\/[^\s]+$/, url) do
      {:pass, %{url: url}}
    else
      {:fail, %{reason: "Output is not a valid URL"}}
    end
  end

  def evaluate(:is_email, output, _opts) do
    email = String.trim(output)

    if Regex.match?(~r/^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$/, email) do
      {:pass, %{email: email}}
    else
      {:fail, %{reason: "Output is not a valid email"}}
    end
  end

  def evaluate(:levenshtein, output, opts) do
    target = opts[:value]
    max_distance = opts[:max_distance] || 3

    distance = levenshtein_distance(output, target)

    if distance <= max_distance do
      {:pass, %{distance: distance, max_distance: max_distance}}
    else
      {:fail,
       %{
         distance: distance,
         max_distance: max_distance,
         reason: "Edit distance #{distance} exceeds max #{max_distance}"
       }}
    end
  end

  # Levenshtein distance algorithm
  defp levenshtein_distance(s1, s2) do
    s1_chars = String.graphemes(s1)
    s2_chars = String.graphemes(s2)
    compute_levenshtein(s1_chars, s2_chars)
  end

  defp compute_levenshtein([], s2_chars), do: length(s2_chars)
  defp compute_levenshtein(s1_chars, []), do: length(s1_chars)

  defp compute_levenshtein(s1_chars, s2_chars) do
    row = Enum.to_list(0..length(s2_chars))

    s1_chars
    |> Enum.with_index()
    |> Enum.reduce(row, fn {c1, i}, prev_row ->
      build_row(c1, i, s2_chars, prev_row)
    end)
    |> List.last()
  end

  defp build_row(c1, i, s2_chars, prev_row) do
    s2_chars
    |> Enum.with_index()
    |> Enum.reduce({[i + 1], i}, fn {c2, j}, {curr, diag} ->
      cost = if c1 == c2, do: 0, else: 1
      new_val = min(min(hd(curr) + 1, Enum.at(prev_row, j + 1) + 1), diag + cost)
      {[new_val | curr], Enum.at(prev_row, j + 1)}
    end)
    |> elem(0)
    |> Enum.reverse()
  end
end
