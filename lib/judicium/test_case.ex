defmodule Judicium.TestCase do
  @moduledoc """
  Represents a single evaluation test case.

  ## Fields

  - `input` - The user query/prompt (required)
  - `actual_output` - The LLM response to evaluate (required for evaluation)
  - `expected_output` - Golden/ideal answer for comparison (optional)
  - `context` - Ground truth context for faithfulness checks (optional)
  - `retrieval_context` - Actual retrieved docs from RAG (optional)
  - `metadata` - Additional info like latency, tokens, cost (optional)

  ## Example

      test_case = %Judicium.TestCase{
        input: "What's the return policy?",
        actual_output: "You can return items within 30 days.",
        context: ["Returns accepted within 30 days with receipt."],
        expected_output: "Items can be returned within 30 days with a receipt."
      }
  """

  @type t :: %__MODULE__{
          input: String.t(),
          actual_output: String.t() | nil,
          expected_output: String.t() | nil,
          context: [String.t()] | String.t() | nil,
          retrieval_context: [String.t()] | nil,
          metadata: map() | nil
        }

  defstruct [
    :input,
    :actual_output,
    :expected_output,
    :context,
    :retrieval_context,
    :metadata
  ]

  @doc """
  Creates a new test case from a map or keyword list.

  ## Examples

      Judicium.TestCase.new(input: "Hello", actual_output: "Hi there!")
      Judicium.TestCase.new(%{"input" => "Hello", "actual_output" => "Hi!"})
  """
  def new(attrs) when is_map(attrs) do
    attrs = normalize_keys(attrs)

    %__MODULE__{
      input: attrs[:input],
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

  defp normalize_keys(map) do
    Map.new(map, fn
      {k, v} when is_binary(k) -> {String.to_existing_atom(k), v}
      {k, v} when is_atom(k) -> {k, v}
    end)
  rescue
    ArgumentError -> Map.new(map, fn {k, v} -> {safe_to_atom(k), v} end)
  end

  defp safe_to_atom(k) when is_binary(k) do
    case k do
      "input" -> :input
      "actual_output" -> :actual_output
      "expected_output" -> :expected_output
      "context" -> :context
      "retrieval_context" -> :retrieval_context
      "metadata" -> :metadata
      _ -> String.to_atom(k)
    end
  end

  defp safe_to_atom(k) when is_atom(k), do: k

  defp normalize_context(nil), do: nil
  defp normalize_context(ctx) when is_binary(ctx), do: [ctx]
  defp normalize_context(ctx) when is_list(ctx), do: ctx
end
