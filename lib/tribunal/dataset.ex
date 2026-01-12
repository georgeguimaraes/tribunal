defmodule Tribunal.Dataset do
  @moduledoc """
  Loads evaluation datasets from JSON or YAML files.

  ## Dataset Format

  Each item in the dataset should have:
  - `input` - The query/prompt (required)
  - `context` - Ground truth context (optional)
  - `expected_output` - Golden answer (optional)
  - `expected` - Assertions to run (optional)

  ## Example JSON

      [
        {
          "input": "What's the return policy?",
          "context": "Returns accepted within 30 days.",
          "expected": {
            "contains": ["30 days"],
            "faithful": {"threshold": 0.8}
          }
        }
      ]

  ## Example YAML

      - input: What's the return policy?
        context: Returns accepted within 30 days.
        expected:
          contains:
            - 30 days
          faithful:
            threshold: 0.8
  """

  alias Tribunal.TestCase

  @doc """
  Loads a dataset from a file path.

  Returns `{:ok, [test_cases]}` or `{:error, reason}`.
  """
  def load(path) do
    with {:ok, content} <- File.read(path),
         {:ok, data} <- parse(path, content) do
      test_cases = Enum.map(data, &to_test_case/1)
      {:ok, test_cases}
    end
  end

  @doc """
  Loads a dataset, raising on error.
  """
  def load!(path) do
    case load(path) do
      {:ok, test_cases} -> test_cases
      {:error, reason} -> raise "Failed to load dataset #{path}: #{inspect(reason)}"
    end
  end

  @doc """
  Loads a dataset and extracts assertions per test case.

  Returns `{:ok, [{test_case, assertions}]}`.
  """
  def load_with_assertions(path) do
    with {:ok, content} <- File.read(path),
         {:ok, data} <- parse(path, content) do
      cases =
        Enum.map(data, fn item ->
          test_case = to_test_case(item)
          assertions = extract_assertions(item)
          {test_case, assertions}
        end)

      {:ok, cases}
    end
  end

  @doc """
  Loads with assertions, raising on error.
  """
  def load_with_assertions!(path) do
    case load_with_assertions(path) do
      {:ok, cases} -> cases
      {:error, reason} -> raise "Failed to load dataset #{path}: #{inspect(reason)}"
    end
  end

  defp parse(path, content) do
    case Path.extname(path) do
      ext when ext in [".json"] ->
        JSON.decode(content)

      ext when ext in [".yaml", ".yml"] ->
        {:ok, YamlElixir.read_from_string!(content)}

      ext ->
        {:error, "Unsupported file format: #{ext}"}
    end
  rescue
    e -> {:error, e}
  end

  defp to_test_case(item) when is_map(item) do
    TestCase.new(item)
  end

  defp extract_assertions(item) when is_map(item) do
    expected = item["expected"] || item[:expected] || %{}
    normalize_assertions(expected)
  end

  defp normalize_assertions(expected) when is_map(expected) do
    Enum.map(expected, fn
      {type, opts} when is_map(opts) ->
        {normalize_type(type), normalize_opts(opts)}

      {type, value} when is_list(value) ->
        {normalize_type(type), [value: value]}

      {type, value} ->
        {normalize_type(type), [value: value]}
    end)
  end

  defp normalize_assertions(expected) when is_list(expected) do
    Enum.map(expected, fn
      type when is_atom(type) -> {type, []}
      type when is_binary(type) -> {normalize_type(type), []}
      {type, opts} -> {normalize_type(type), normalize_opts(opts)}
    end)
  end

  defp normalize_type(type) when is_binary(type), do: String.to_existing_atom(type)
  defp normalize_type(type) when is_atom(type), do: type

  defp normalize_opts(opts) when is_map(opts) do
    Enum.map(opts, fn
      {k, v} when is_binary(k) -> {String.to_existing_atom(k), v}
      {k, v} when is_atom(k) -> {k, v}
    end)
  rescue
    ArgumentError ->
      Enum.map(opts, fn
        {"threshold", v} -> {:threshold, v}
        {"value", v} -> {:value, v}
        {"values", v} -> {:values, v}
        {"max", v} -> {:max, v}
        {"pattern", v} -> {:pattern, v}
        {k, v} when is_binary(k) -> {String.to_atom(k), v}
        {k, v} -> {k, v}
      end)
  end

  defp normalize_opts(opts) when is_list(opts), do: opts
end
