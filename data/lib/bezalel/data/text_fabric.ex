defmodule Bezalel.Data.TextFabric do
  @moduledoc """
  Reads Text-Fabric feature files (`.tf`), the format of ETCBC/dss and of
  DT-UCPH/sp (the Samaritan Pentateuch): a header of `@key=value` lines, a
  blank line, then one data line per node.
  A data line is `value` (the node after the previous one) or
  `spec<TAB>value`, where `spec` is a node, a range `3-5` or a list
  `1,4-6`; nodes only increase. `otype.tf` maps node ranges to types and
  `oslots.tf` maps each non-slot node to its slots.

  A port of studybible-mcp's `_tf_data`, `_tf_ranges`, `_tf_feature` and
  `_tf_types` (`corpora/qumran.py`, MIT), which read the same files for the
  ancient pack's Qumran works. Every file must carry the CC BY-NC 4.0
  declaration both releases are published under (ETCBC spells the key
  `@license`, DT-UCPH `@licence`).
  """

  @licence "@license=Creative Commons Attribution-NonCommercial 4.0 International License"
  @licences [
    @licence,
    "@licence=Creative Commons Attribution-NonCommercial 4.0 International License"
  ]

  @type ranges :: [{pos_integer(), pos_integer()}]

  @doc "ETCBC's licence line; a feature file's header must have it or DT-UCPH's `@licence=` spelling."
  @spec licence() :: String.t()
  def licence, do: @licence

  @doc """
  The data lines of a feature file, after checking its header: every header
  line starts with `@` and one is the licence declaration. Raises otherwise.
  """
  @spec data_lines(String.t(), binary()) :: [binary()]
  def data_lines(name, bytes) do
    {header, data} = bytes |> :binary.split(["\r\n", "\n"], [:global]) |> split_header([])

    Enum.each(header, fn line ->
      unless String.starts_with?(line, "@") do
        raise ArgumentError, "#{name}: malformed Text-Fabric header line #{inspect(line)}"
      end
    end)

    unless Enum.any?(@licences, &(&1 in header)) do
      raise ArgumentError, "#{name}: no CC BY-NC 4.0 declaration in the header"
    end

    case List.last(data) do
      "" -> Enum.drop(data, -1)
      _ -> data
    end
  end

  defp split_header(["" | rest], header), do: {Enum.reverse(header), rest}
  defp split_header([line | rest], header), do: split_header(rest, [line | header])
  defp split_header([], header), do: {Enum.reverse(header), []}

  @doc "The node ranges of a spec: '7' -> [{7, 7}], '1,4-6' -> [{1, 1}, {4, 6}]."
  @spec ranges(String.t()) :: ranges()
  def ranges(spec) do
    spec
    |> String.split(",")
    |> Enum.map(fn part ->
      case String.split(part, "-", parts: 2) do
        [first] -> {integer!(first, spec), integer!(first, spec)}
        [first, last] -> {integer!(first, spec), integer!(last, spec)}
      end
    end)
  end

  defp integer!(text, spec) do
    case Integer.parse(text) do
      {value, ""} when value > 0 -> value
      _ -> raise ArgumentError, "malformed node spec #{inspect(spec)}"
    end
  end

  @doc "A value with Text-Fabric's escapes (`\\\\`, `\\t`, `\\n`) undone."
  @spec unescape(binary()) :: binary()
  def unescape(value) do
    if String.contains?(value, "\\"), do: unescape(value, ""), else: value
  end

  defp unescape(<<"\\\\", rest::binary>>, acc), do: unescape(rest, acc <> "\\")
  defp unescape(<<"\\t", rest::binary>>, acc), do: unescape(rest, acc <> "\t")
  defp unescape(<<"\\n", rest::binary>>, acc), do: unescape(rest, acc <> "\n")

  defp unescape(<<char::utf8, rest::binary>>, acc),
    do: unescape(rest, <<acc::binary, char::utf8>>)

  defp unescape(<<>>, acc), do: acc

  @doc """
  The values of a node feature (or `oslots`) for nodes `first..last`, as a
  map. Nodes outside the range are skipped; reading stops after `last`.
  """
  @spec feature(String.t(), binary(), pos_integer(), pos_integer()) :: %{
          pos_integer() => binary()
        }
  def feature(name, bytes, first, last) do
    name
    |> data_lines(bytes)
    |> Enum.reduce_while({0, %{}}, fn line, {node, values} ->
      {spec, value} =
        case :binary.split(line, "\t") do
          [value] -> {Integer.to_string(node + 1), value}
          [spec, value] -> {spec, value}
        end

      value = unescape(value)

      {node, values} =
        Enum.reduce(ranges(spec), {node, values}, &put_range(&1, &2, value, {name, first, last}))

      if node >= last, do: {:halt, {node, values}}, else: {:cont, {node, values}}
    end)
    |> elem(1)
  end

  # Stores `value` for the nodes of one range inside first..last.
  defp put_range({start, stop}, {previous, values}, value, {name, first, last}) do
    if start <= previous do
      raise ArgumentError, "#{name}: node #{start} does not follow node #{previous}"
    end

    low = max(start, first)
    high = min(stop, last)

    values =
      if low <= high,
        do: Enum.reduce(low..high//1, values, &Map.put(&2, &1, value)),
        else: values

    {stop, values}
  end

  @doc """
  The node range of each node type, from `otype.tf`; raises unless every
  type in `required` is there (ETCBC/dss: signs and lines; the Samaritan
  Pentateuch has no lines).
  """
  @spec types(binary(), [String.t()]) :: %{String.t() => {pos_integer(), pos_integer()}}
  def types(bytes, required \\ ["sign", "line"]) do
    types =
      for line <- data_lines("otype.tf", bytes), line != "", into: %{} do
        case :binary.split(line, "\t") do
          [spec, name] ->
            [range] = ranges(spec)
            {name, range}

          _ ->
            raise ArgumentError, "otype.tf: malformed type line #{inspect(line)}"
        end
      end

    for name <- required, not Map.has_key?(types, name) do
      raise ArgumentError, "otype.tf: no #{inspect(name)} nodes"
    end

    types
  end

  @doc "The slots of each node `first..last` (from `oslots.tf`), as one range each; raises on a gap."
  @spec slots(binary(), pos_integer(), pos_integer()) :: %{pos_integer() => Range.t()}
  def slots(bytes, first, last) do
    "oslots.tf"
    |> feature(bytes, first, last)
    |> Map.new(fn {node, spec} ->
      case ranges(spec) do
        [{low, high}] -> {node, low..high}
        _ -> raise ArgumentError, "oslots.tf: node #{node} has discontinuous slots"
      end
    end)
  end
end
