defmodule Tribunal.Dataset do
  @moduledoc """
  Loads evaluation datasets from JSON or YAML files.

  ## Dataset Format

  Each item in the dataset should have:
  - `input` - The JSON-compatible input passed to the system under test (required)
  - `evaluation_input` - Optional text representation shown to judges
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

  @known_option_keys ~w(
    actual alike_fn context expected latency llm max max_distance max_tokens min model
    pattern policy purpose query temperature threshold value values verbose
  )a

  @doc """
  Loads a dataset from a file path.

  Returns `{:ok, [test_cases]}` or `{:error, reason}`.
  """
  def load(path) do
    with {:ok, content} <- File.read(path),
         {:ok, data} <- parse(path, content),
         :ok <- validate(data) do
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
         {:ok, data} <- parse(path, content),
         :ok <- validate(data) do
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

  defp validate(data) when not is_list(data),
    do: {:error, {:invalid_dataset, "top-level value must be a list"}}

  defp validate(data) do
    data
    |> Enum.with_index()
    |> Enum.reduce_while(:ok, fn {item, index}, :ok ->
      case validate_item(item) do
        :ok -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, {:invalid_case, index, reason}}}
      end
    end)
  end

  defp validate_item(item) when not is_map(item), do: {:error, "case must be an object"}

  defp validate_item(item) do
    input = field(item, "input", :input)
    expected = field(item, "expected", :expected)

    with :ok <- validate_case_keys(item),
         :ok <- require_input(input),
         :ok <-
           optional_string(field(item, "evaluation_input", :evaluation_input), "evaluation_input"),
         :ok <- optional_string(field(item, "actual_output", :actual_output), "actual_output"),
         :ok <-
           optional_string(field(item, "expected_output", :expected_output), "expected_output"),
         :ok <- optional_context(field(item, "context", :context), "context"),
         :ok <-
           optional_context(
             field(item, "retrieval_context", :retrieval_context),
             "retrieval_context"
           ),
         :ok <- optional_map(field(item, "metadata", :metadata), "metadata") do
      validate_expected(expected)
    end
  end

  defp validate_case_keys(item) do
    if Enum.all?(Map.keys(item), &(is_binary(&1) or is_atom(&1))) do
      :ok
    else
      {:error, "case field names must be strings or atoms"}
    end
  end

  defp field(item, string_key, atom_key) do
    case Map.fetch(item, string_key) do
      {:ok, value} -> value
      :error -> Map.get(item, atom_key)
    end
  end

  defp require_input(nil), do: {:error, "input is required"}
  defp require_input(value), do: TestCase.validate_input(value)

  defp optional_string(nil, _field), do: :ok
  defp optional_string(value, _field) when is_binary(value), do: :ok
  defp optional_string(_value, field), do: {:error, "#{field} must be a string"}

  defp optional_context(nil, _field), do: :ok
  defp optional_context(value, _field) when is_binary(value), do: :ok

  defp optional_context(value, field) when is_list(value) do
    if Enum.all?(value, &is_binary/1),
      do: :ok,
      else: {:error, "#{field} items must be strings"}
  end

  defp optional_context(_value, field),
    do: {:error, "#{field} must be a string or list of strings"}

  defp optional_map(nil, _field), do: :ok
  defp optional_map(value, _field) when is_map(value), do: :ok
  defp optional_map(_value, field), do: {:error, "#{field} must be an object"}

  defp validate_expected(nil), do: :ok

  defp validate_expected(expected) when is_map(expected) do
    if Enum.all?(expected, fn {type, opts} ->
         (is_binary(type) or is_atom(type)) and valid_assertion_value?(opts)
       end) do
      :ok
    else
      {:error, "expected assertions must use string or atom names and valid options"}
    end
  end

  defp validate_expected(expected) when is_list(expected) do
    if Enum.all?(expected, &(is_binary(&1) or is_atom(&1) or valid_assertion_tuple?(&1))) do
      :ok
    else
      {:error, "expected list items must be assertion names or {name, options} tuples"}
    end
  end

  defp validate_expected(_expected), do: {:error, "expected must be an object or list"}

  defp valid_assertion_tuple?({type, opts}) when is_atom(type) or is_binary(type),
    do: valid_assertion_options?(opts)

  defp valid_assertion_tuple?(_item), do: false

  defp valid_assertion_value?(opts) when is_map(opts), do: valid_assertion_options?(opts)
  defp valid_assertion_value?(_value), do: true

  defp valid_assertion_options?(opts) when is_map(opts) do
    Enum.all?(Map.keys(opts), &(is_binary(&1) or is_atom(&1)))
  end

  defp valid_assertion_options?(opts) when is_list(opts), do: Keyword.keyword?(opts)
  defp valid_assertion_options?(_opts), do: false

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

  defp normalize_type(type) when is_binary(type) do
    Tribunal.Assertions.resolve_type(type)
  end

  defp normalize_type(type) when is_atom(type), do: type

  defp normalize_opts(opts) when is_map(opts) do
    Enum.map(opts, fn
      {k, v} when is_binary(k) -> {normalize_option_key(k), v}
      {k, v} when is_atom(k) -> {k, v}
    end)
  end

  defp normalize_opts(opts) when is_list(opts), do: opts

  defp normalize_option_key(value) do
    Enum.find(@known_option_keys, value, &(Atom.to_string(&1) == value))
    |> case do
      ^value -> existing_atom_or_string(value)
      key -> key
    end
  end

  defp existing_atom_or_string(value) do
    String.to_existing_atom(value)
  rescue
    ArgumentError -> value
  end
end
