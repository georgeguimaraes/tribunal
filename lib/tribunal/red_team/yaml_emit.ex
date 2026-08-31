defmodule Tribunal.RedTeam.YamlEmit do
  @moduledoc """
  Emits a list of red-team cases as a tribunal-shaped dataset YAML.

  Strings are quoted before passing the dataset to `Ymlr`. This keeps
  model-provided values from being interpreted as YAML syntax or scalar types
  when the dataset is loaded again through `Tribunal.Dataset`.
  """

  defmodule QuotedString do
    @moduledoc false
    defstruct [:value]
  end

  @doc "Encodes a list of red-team cases to a YAML string."
  def encode(cases) when is_list(cases) do
    cases
    |> quote_strings()
    |> Ymlr.Encode.to_s!(sort_maps: true)
    |> Kernel.<>("\n")
  end

  defp quote_strings(value) when is_binary(value), do: %QuotedString{value: value}

  defp quote_strings(value) when is_map(value) do
    Map.new(value, fn {key, child} -> {key, quote_strings(child)} end)
  end

  defp quote_strings(value) when is_list(value) do
    if value != [] and Keyword.keyword?(value) do
      value |> Map.new() |> quote_strings()
    else
      Enum.map(value, &quote_strings/1)
    end
  end

  defp quote_strings(value), do: value
end

defimpl Ymlr.Encoder, for: Tribunal.RedTeam.YamlEmit.QuotedString do
  def encode(%{value: value}, _indent_level, _opts), do: JSON.encode!(value)
end
