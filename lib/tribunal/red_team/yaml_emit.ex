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
    [
      encode_kv("input", input, "- ", 0),
      encode_kv("metadata", metadata, "  ", 1),
      encode_kv("expected", expected, "  ", 1)
    ]
    |> Enum.join("\n")
  end

  defp encode_kv(key, value, prefix, level) when is_binary(value) do
    if String.contains?(value, "\n") do
      pad = pad(level + 1)

      lines =
        value
        |> String.split("\n")
        |> Enum.map_join("\n", fn
          "" -> ""
          line -> pad <> line
        end)

      prefix <> "#{key}: |\n" <> lines
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

  defp encode_kv(key, value, prefix, _level) when is_boolean(value) do
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

  defp ordered_pairs(map) do
    map
    |> Enum.to_list()
    |> Enum.sort_by(fn {k, _v} -> {Map.get(@order_hints, k, 99), to_string(k)} end)
  end

  defp pad(level), do: String.duplicate("  ", level)

  defp scalar(""), do: "''"

  defp scalar(value) when is_binary(value) do
    if needs_quoting?(value), do: double_quote(value), else: value
  end

  defp scalar(value) when is_atom(value), do: Atom.to_string(value)
  defp scalar(value), do: to_string(value)

  defp needs_quoting?(string) do
    String.match?(string, ~r/^[\s\-?:,\[\]\{\}#&*!|>'"%@`]/) or
      String.contains?(string, ": ") or
      String.contains?(string, " #") or
      String.ends_with?(string, ":") or
      string in ["true", "false", "null", "yes", "no", "on", "off", "~"]
  end

  defp double_quote(string) do
    escaped =
      string
      |> String.replace("\\", "\\\\")
      |> String.replace("\"", "\\\"")
      |> String.replace("\t", "\\t")
      |> String.replace("\n", "\\n")

    "\"" <> escaped <> "\""
  end
end
