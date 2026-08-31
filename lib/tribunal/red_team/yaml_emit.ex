defmodule Tribunal.RedTeam.YamlEmit do
  @moduledoc """
  Emits a list of red-team cases as a tribunal-shaped dataset YAML.

  Targets the specific shape produced by `Tribunal.RedTeam.generate/1`: each
  case is `%{input: string, metadata: map, expected: map}`. The output
  round-trips through `Tribunal.Dataset.load/1`.

  Not a general-purpose YAML emitter. Handles strings (single- and multi-line),
  atoms, numbers, maps, keyword lists, and lists of scalars — the value types
  that appear in red-team case structures.
  """

  @order_hints %{
    plugin: 1,
    severity: 2,
    goal: 3,
    purpose: 4,
    policy_violation: 1,
    policy: 1
  }

  @doc "Encodes a list of red-team cases to a YAML string."
  def encode(cases) when is_list(cases) do
    cases
    |> Enum.map_join("\n", &encode_case/1)
    |> Kernel.<>("\n")
  end

  defp encode_case(%{input: input, metadata: metadata, expected: expected}) do
    # input/metadata/expected are keys of a mapping nested inside a sequence
    # item ("- "), so they sit at mapping level 1. Passing level 1 keeps
    # multi-line block scalars indented past the sibling keys.
    [
      encode_kv("input", input, "- ", 1),
      encode_kv("metadata", metadata, "  ", 1),
      encode_kv("expected", expected, "  ", 1)
    ]
    |> Enum.join("\n")
  end

  defp encode_kv(key, value, prefix, level) when is_binary(value) do
    if String.contains?(value, "\n") and not String.contains?(value, "\r") do
      pad = pad(level + 1)
      indicator = block_indicator(value)

      lines =
        value
        |> block_content()
        |> String.split("\n")
        |> Enum.map_join("\n", fn
          "" -> ""
          line -> pad <> line
        end)

      prefix <> "#{key}: #{indicator}\n" <> lines
    else
      prefix <> "#{key}: " <> scalar(value)
    end
  end

  defp encode_kv(key, value, prefix, _level) when is_atom(value) do
    prefix <> "#{key}: " <> Atom.to_string(value)
  end

  defp encode_kv(key, value, prefix, _level) when is_number(value) do
    prefix <> "#{key}: " <> to_string(value)
  end

  defp encode_kv(key, value, prefix, level) when is_map(value) do
    case ordered_pairs(value) do
      [] ->
        prefix <> "#{key}: {}"

      pairs ->
        child_pad = pad(level + 1)

        children =
          Enum.map_join(pairs, "\n", fn {k, v} ->
            encode_kv(to_string(k), v, child_pad, level + 1)
          end)

        prefix <> "#{key}:\n" <> children
    end
  end

  defp encode_kv(key, value, prefix, level) when is_list(value) do
    cond do
      value == [] ->
        prefix <> "#{key}: []"

      Keyword.keyword?(value) ->
        encode_kv(key, Map.new(value), prefix, level)

      true ->
        child_pad = pad(level + 1)
        items = Enum.map_join(value, "\n", fn item -> child_pad <> "- " <> scalar(item) end)
        prefix <> "#{key}:\n" <> items
    end
  end

  defp block_indicator(value) do
    cond do
      String.ends_with?(value, "\n\n") -> "|+"
      String.ends_with?(value, "\n") -> "|"
      true -> "|-"
    end
  end

  defp block_content(value) do
    if String.ends_with?(value, "\n") do
      binary_part(value, 0, byte_size(value) - 1)
    else
      value
    end
  end

  defp ordered_pairs(map) do
    map
    |> Enum.to_list()
    |> Enum.sort_by(fn {k, _v} -> {Map.get(@order_hints, k, 99), to_string(k)} end)
  end

  defp pad(level), do: String.duplicate("  ", level)

  defp scalar("") do
    JSON.encode!("")
  end

  defp scalar(value) when is_binary(value), do: JSON.encode!(value)

  defp scalar(value) when is_atom(value), do: Atom.to_string(value)
  defp scalar(value), do: to_string(value)
end
