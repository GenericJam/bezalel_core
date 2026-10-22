defmodule Bezalel.Data.Xml do
  @moduledoc """
  Reads an XML document into a plain tree with OTP's SAX parser
  (`:xmerl_sax_parser`): each element is `{name, attributes, children,
  line}`, `attributes` a map, `children` elements and text (binaries, the
  parser's runs of characters joined), `line` where the element starts.
  Small and strict: the importers that use it check every element name
  they meet, so unknown markup stops the build.
  """

  @type element ::
          {String.t(), %{String.t() => String.t()}, [element() | String.t()], pos_integer()}

  @doc "The root element of `bytes`; raises on malformed XML (`name` names the file)."
  @spec parse!(String.t(), binary()) :: element()
  def parse!(name, bytes) do
    case :xmerl_sax_parser.stream(bytes, event_fun: &event/3, event_state: [{:root, %{}, [], 0}]) do
      {:ok, [{:root, _, [root], _}], _rest} ->
        root

      {:ok, state, _rest} ->
        raise ArgumentError, "#{name}: unbalanced XML (#{length(state)} open)"

      other ->
        raise ArgumentError, "#{name}: malformed XML: #{inspect(other, limit: 5)}"
    end
  end

  defp event({:startElement, _uri, _local, {_prefix, name}, attributes}, {_, _, line}, stack) do
    attributes =
      Map.new(attributes, fn {_uri, _prefix, key, value} ->
        {List.to_string(key), List.to_string(value)}
      end)

    [{List.to_string(name), attributes, [], line} | stack]
  end

  defp event({:endElement, _uri, _local, _qname}, _location, [element, parent | stack]) do
    {name, attributes, children, line} = element
    {pname, pattributes, pchildren, pline} = parent
    done = {name, attributes, join_text(Enum.reverse(children)), line}
    [{pname, pattributes, [done | pchildren], pline} | stack]
  end

  defp event({:characters, chars}, _location, [{name, attributes, children, line} | stack]),
    do: [{name, attributes, [List.to_string(chars) | children], line} | stack]

  defp event(_event, _location, stack), do: stack

  # Adjacent runs of characters as one binary.
  defp join_text(children) do
    children
    |> Enum.chunk_by(&is_binary/1)
    |> Enum.flat_map(fn
      [text | _] = run when is_binary(text) -> [Enum.join(run)]
      elements -> elements
    end)
  end

  @doc """
  The text of an element that holds only text; raises if it has child
  elements (markup the importer doesn't know).
  """
  @spec text(element()) :: String.t()
  def text({name, _attributes, children, line}) do
    if Enum.any?(children, &is_tuple/1) do
      raise ArgumentError, "line #{line}: <#{name}> has markup inside it"
    end

    Enum.join(children)
  end

  @doc "An element's child elements (whitespace between them dropped)."
  @spec elements(element()) :: [element()]
  def elements({_name, _attributes, children, _line}), do: Enum.filter(children, &is_tuple/1)
end
