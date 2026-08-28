defmodule Tribunal.TestCase do
  @moduledoc """
  Represents a single evaluation test case.

  ## Fields

  - `input` - The JSON-compatible input passed to the system under test (required)
  - `evaluation_input` - Optional text representation shown to judges
  - `actual_output` - The LLM response to evaluate (required for evaluation)
  - `expected_output` - Golden/ideal answer for comparison (optional)
  - `context` - Ground truth context for faithfulness checks (optional)
  - `retrieval_context` - Actual retrieved docs from RAG (optional)
  - `metadata` - Additional info like latency, tokens, cost (optional)

  ## Example

      test_case = %Tribunal.TestCase{
        input: "What's the return policy?",
        actual_output: "You can return items within 30 days.",
        context: ["Returns accepted within 30 days with receipt."],
        expected_output: "Items can be returned within 30 days with a receipt."
      }
  """

  @type t :: %__MODULE__{
          input: json_value(),
          evaluation_input: String.t() | nil,
          actual_output: String.t() | nil,
          expected_output: String.t() | nil,
          context: [String.t()] | String.t() | nil,
          retrieval_context: [String.t()] | nil,
          metadata: map() | nil
        }

  @type json_scalar :: String.t() | number() | boolean() | nil
  @type json_value :: json_scalar() | [json_value()] | %{String.t() => json_value()}

  defstruct [
    :input,
    :evaluation_input,
    :actual_output,
    :expected_output,
    :context,
    :retrieval_context,
    :metadata
  ]

  @doc """
  Creates a new test case from a map or keyword list.

  ## Examples

      Tribunal.TestCase.new(input: "Hello", actual_output: "Hi there!")
      Tribunal.TestCase.new(%{"input" => "Hello", "actual_output" => "Hi!"})
  """
  def new(attrs) when is_map(attrs) do
    attrs = normalize_keys(attrs)

    %__MODULE__{
      input: attrs[:input],
      evaluation_input: attrs[:evaluation_input],
      actual_output: attrs[:actual_output],
      expected_output: attrs[:expected_output],
      context: normalize_context(attrs[:context]),
      retrieval_context: normalize_context(attrs[:retrieval_context]),
      metadata: attrs[:metadata]
    }
  end

  def new(attrs) when is_list(attrs) do
    attrs |> Map.new() |> new()
  end

  @doc """
  Sets the actual output on an existing test case.
  Useful when the dataset provides input/context but output comes from your LLM.
  """
  def with_output(%__MODULE__{} = test_case, output) do
    %{test_case | actual_output: output}
  end

  @doc """
  Sets the retrieval context from your RAG pipeline.
  """
  def with_retrieval_context(%__MODULE__{} = test_case, context) do
    %{test_case | retrieval_context: normalize_context(context)}
  end

  @doc """
  Adds metadata (latency, tokens, cost, etc).
  """
  def with_metadata(%__MODULE__{} = test_case, metadata) when is_map(metadata) do
    existing = test_case.metadata || %{}
    %{test_case | metadata: Map.merge(existing, metadata)}
  end

  @doc """
  Validates the fields required before a test case is passed to a provider or evaluator.
  """
  @spec validate(t()) :: :ok | {:error, String.t()}
  def validate(%__MODULE__{input: nil}), do: {:error, "input is required"}

  def validate(%__MODULE__{input: input, evaluation_input: evaluation_input}) do
    case validate_input(input) do
      :ok -> validate_evaluation_input(evaluation_input)
      error -> error
    end
  end

  @doc """
  Validates that an input can be represented in JSON without changing its shape.
  """
  @spec validate_input(term()) :: :ok | {:error, String.t()}
  def validate_input(value) when is_map(value) do
    if json_value?(value),
      do: :ok,
      else: {:error, "input maps must use string keys and JSON-compatible values"}
  end

  def validate_input(value) do
    if json_value?(value),
      do: :ok,
      else: {:error, "input must be JSON-compatible"}
  end

  @doc """
  Returns the text judges should evaluate for a test case.

  An explicit `evaluation_input` wins. String inputs remain unchanged and structured
  inputs use their JSON representation.
  """
  @spec evaluation_input(t()) :: String.t()
  def evaluation_input(%__MODULE__{evaluation_input: value}) when is_binary(value), do: value
  def evaluation_input(%__MODULE__{input: value}) when is_binary(value), do: value
  def evaluation_input(%__MODULE__{input: value}), do: JSON.encode!(value)

  @doc """
  Returns a safe, human-readable representation of an input for reports and test names.
  """
  @spec display_input(t() | term()) :: String.t()
  def display_input(%__MODULE__{} = test_case), do: display_input(test_case.input)
  def display_input(value) when is_binary(value), do: value

  def display_input(value) do
    case encode_json(value) do
      {:ok, encoded} -> encoded
      {:error, _reason} -> inspect(value)
    end
  end

  @doc false
  def display_name(%__MODULE__{} = test_case, max_length \\ 80) do
    test_case
    |> preferred_name()
    |> String.slice(0, max_length)
    |> String.trim()
  end

  defp preferred_name(%__MODULE__{metadata: metadata} = test_case) when is_map(metadata) do
    case Map.get(metadata, "name") || Map.get(metadata, :name) do
      value when is_binary(value) -> value
      _value -> display_input(test_case)
    end
  end

  defp preferred_name(test_case), do: display_input(test_case)

  defp normalize_keys(map) do
    fields = MapSet.new(__struct__() |> Map.from_struct() |> Map.keys())

    Enum.reduce(map, %{}, fn
      {key, value}, acc when is_atom(key) ->
        if MapSet.member?(fields, key), do: Map.put(acc, key, value), else: acc

      {key, value}, acc when is_binary(key) ->
        case Enum.find(fields, &(Atom.to_string(&1) == key)) do
          nil -> acc
          field -> Map.put(acc, field, value)
        end
    end)
  end

  defp normalize_context(nil), do: nil
  defp normalize_context(ctx) when is_binary(ctx), do: [ctx]
  defp normalize_context(ctx) when is_list(ctx), do: ctx

  defp validate_evaluation_input(nil), do: :ok
  defp validate_evaluation_input(value) when is_binary(value), do: :ok
  defp validate_evaluation_input(_value), do: {:error, "evaluation_input must be a string"}

  defp json_value?(value) when is_nil(value) or is_integer(value) or is_boolean(value), do: true
  defp json_value?(value) when is_binary(value), do: String.valid?(value)

  defp json_value?(value) when is_float(value) do
    match?({:ok, _encoded}, encode_json(value))
  end

  defp json_value?([]), do: true
  defp json_value?([_head | _tail] = values), do: json_list?(values)

  defp json_value?(value) when is_map(value) do
    Enum.all?(value, fn {key, item} ->
      is_binary(key) and String.valid?(key) and json_value?(item)
    end)
  end

  defp json_value?(_value), do: false

  defp json_list?([]), do: true
  defp json_list?([head | tail]), do: json_value?(head) and json_list?(tail)
  defp json_list?(_improper_tail), do: false

  defp encode_json(value) do
    {:ok, JSON.encode!(value)}
  rescue
    _exception -> {:error, :invalid_json_value}
  catch
    _kind, _reason -> {:error, :invalid_json_value}
  end
end
