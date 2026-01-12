defmodule Tribunal.Assertions.Embedding do
  @moduledoc """
  Embedding-based semantic similarity assertions.

  Requires `alike` dependency. Uses sentence embeddings to determine
  if two texts are semantically similar.
  """

  @default_threshold 0.7

  @embedding_types [:similar]

  @doc """
  Returns list of available embedding assertion types.
  """
  def available, do: @embedding_types

  @doc """
  Evaluates semantic similarity between actual and expected output.

  ## Options

    * `:threshold` - Similarity threshold (0.0 to 1.0). Default: 0.7
    * `:alike_fn` - Custom similarity function for testing (default: Alike.similarity/3)

  ## Examples

      test_case = %TestCase{
        actual_output: "The cat is sleeping",
        expected_output: "A feline is resting"
      }

      {:pass, %{similarity: 0.85}} = Embedding.evaluate(test_case, threshold: 0.8)

  """
  def evaluate(test_case, opts \\ [])

  def evaluate(%{expected_output: nil}, _opts) do
    {:error, "Similar assertion requires expected_output to be provided"}
  end

  def evaluate(test_case, opts) do
    threshold = opts[:threshold] || @default_threshold
    alike_fn = opts[:alike_fn] || (&default_similarity/3)

    case alike_fn.(test_case.actual_output, test_case.expected_output, opts) do
      {:ok, similarity} when similarity >= threshold ->
        {:pass, %{similarity: similarity, threshold: threshold}}

      {:ok, similarity} ->
        {:fail,
         %{
           similarity: similarity,
           threshold: threshold,
           reason:
             "Output is not semantically similar to expected (#{Float.round(similarity, 2)} < #{threshold})"
         }}

      {:error, reason} ->
        {:error, "Failed to compute similarity: #{inspect(reason)}"}
    end
  end

  defp default_similarity(sentence1, sentence2, opts) do
    if Code.ensure_loaded?(Alike) do
      Alike.similarity(sentence1, sentence2, opts)
    else
      {:error, "alike is not available. Add {:alike, \"~> 0.4\"} to your dependencies."}
    end
  end
end
