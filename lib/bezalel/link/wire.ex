defmodule Bezalel.Link.Wire do
  @moduledoc """
  The link's frames (`Bezalel.Link.Handshake` seals them): JSON objects
  with an `"op"`, a request's `"id"` (the sender's, unique per connection)
  and an answer's `"re"` (the id it answers). Binary content (session
  bytes, a material's bytes) travels as unpadded base64url in chunks of
  at most `chunk_size/0` raw bytes, `%{"offset", "bytes", "eof"}`, at most
  `window/0` unacknowledged at a time, so a sealed frame stays well under
  `max_frame/0` (the server's WebSocket limit).

  `ops/0` lists version 1's operations by direction; a receiver answers an
  op it doesn't know with `error/2`'s `"unknown_op"` rather than failing.
  """

  @max_frame 1_048_576
  @chunk_size 262_144
  @window 4
  @max_bytes 268_435_456
  @max_chunks 4096

  @ops %{
    handshake: ~w(hello auth welcome),
    pairing: ~w(pair.claim pair.approve pair.reject pair.info sessions.list sessions.revoke
      sessions.changed),
    credentials: ~w(cred.snapshot cred.set cred.delete cred.rotated cred.refresh cred.request),
    index: ~w(index.snapshot index.upsert index.remove prefs prefs.set),
    conversations: ~w(conv.pull conv.append conv.create conv.meta conv.delete conv.import
      conv.data conv.changed conv.reset conv.hold conv.release),
    materials: ~w(mat.get mat.put mat.data),
    misc: ~w(ack error push.token usage.add)
  }

  @doc "The largest frame a side accepts, in bytes (1 MiB)."
  @spec max_frame() :: pos_integer()
  def max_frame, do: @max_frame

  @doc "A chunk's raw bytes at most (256 KiB; base64 makes it about 350 KiB)."
  @spec chunk_size() :: pos_integer()
  def chunk_size, do: @chunk_size

  @doc "How many chunks may be in flight before the sender waits for an `ack`."
  @spec window() :: pos_integer()
  def window, do: @window

  @doc """
  The most bytes `assemble/3` puts together by default (256 MiB: the
  phone keeps a material of up to 250 MB).
  """
  @spec max_bytes() :: pos_integer()
  def max_bytes, do: @max_bytes

  @doc """
  The most chunks `assemble/3` takes for one assembly by default, empty
  ones included (4096: `max_bytes/0` takes 1024 of `chunk_size/0`).
  """
  @spec max_chunks() :: pos_integer()
  def max_chunks, do: @max_chunks

  @doc "Version 1's ops, by group."
  @spec ops() :: %{atom() => [String.t()]}
  def ops, do: @ops

  @doc "Is `op` one of version 1's?"
  @spec known_op?(String.t()) :: boolean()
  def known_op?(op), do: Enum.any?(@ops, fn {_group, ops} -> op in ops end)

  @doc "A frame: `op` and its `fields` (string keys), optionally a request `id`."
  @spec frame(String.t(), map(), String.t() | integer() | nil) :: map()
  def frame(op, fields \\ %{}, id \\ nil) when is_binary(op) do
    frame = Map.put(stringify(fields), "op", op)
    if id == nil, do: frame, else: Map.put(frame, "id", id)
  end

  @doc ~s|The answer to `request` (a decoded frame with an "id"): `op` and `fields`, "re" its id.|
  @spec reply(map(), String.t(), map()) :: map()
  def reply(%{"id" => id}, op, fields \\ %{}),
    do: fields |> stringify() |> Map.merge(%{"op" => op, "re" => id})

  @doc "An error answer to `request`: `code` (e.g. `\"unknown_op\"`) and a message for logs."
  @spec error(map(), String.t(), String.t()) :: map()
  def error(request, code, message \\ ""),
    do: reply(request, "error", %{"code" => code, "message" => message})

  @doc "The frame as JSON."
  @spec encode(map()) :: binary()
  def encode(%{"op" => op} = frame) when is_binary(op), do: Jason.encode!(frame)

  @doc """
  A frame from JSON: `{:ok, frame}`, or `{:error, reason}`: `:too_large`,
  `:not_json` (also anything not a binary), `:no_op` (not an object with a
  string `"op"`).
  """
  @spec decode(term()) :: {:ok, map()} | {:error, :too_large | :not_json | :no_op}
  def decode(json) when is_binary(json) and byte_size(json) > @max_frame,
    do: {:error, :too_large}

  def decode(json) when is_binary(json) do
    case Jason.decode(json) do
      {:ok, %{"op" => op} = frame} when is_binary(op) -> {:ok, frame}
      {:ok, _other} -> {:error, :no_op}
      {:error, _} -> {:error, :not_json}
    end
  end

  def decode(_other), do: {:error, :not_json}

  # ── chunks ──

  @doc """
  `bytes` (which start at `offset` in what they are part of) as chunk
  fields, in order: `%{"offset", "bytes" (base64url), "eof"}`, the last
  one `"eof" => true`. Empty `bytes` is one empty chunk. `opts`:
  `:chunk_size`.
  """
  @spec chunks(binary(), non_neg_integer(), keyword()) :: [map()]
  def chunks(bytes, offset \\ 0, opts \\ []) when is_binary(bytes) do
    size = Keyword.get(opts, :chunk_size, @chunk_size)
    total = byte_size(bytes)

    if total == 0 do
      [%{"offset" => offset, "bytes" => "", "eof" => true}]
    else
      for at <- 0..(total - 1)//size do
        part = binary_part(bytes, at, min(size, total - at))
        %{"offset" => offset + at, "bytes" => b64(part), "eof" => at + size >= total}
      end
    end
  end

  defmodule Assembly do
    @moduledoc "Chunks being put back together (`Bezalel.Link.Wire.assemble/3`)."
    @enforce_keys [:offset]
    defstruct [:offset, parts: [], size: 0, chunks: 0]

    @type t :: %__MODULE__{
            offset: non_neg_integer(),
            parts: [binary()],
            size: non_neg_integer(),
            chunks: non_neg_integer()
          }
  end

  @doc "An empty assembly of bytes that start at `offset`."
  @spec assembly(non_neg_integer()) :: Assembly.t()
  def assembly(offset \\ 0), do: %Assembly{offset: offset}

  @doc """
  Adds the next chunk: `{:more, assembly}`, `{:done, bytes}` after the
  `"eof"` one, or `{:error, reason}`: `:out_of_order` (not the next
  offset; a resend of one already added is `{:more, assembly}` unchanged),
  `:bad_chunk`, `:too_large` (more than `opts[:max_bytes]` bytes, by
  default `max_bytes/0`, or more than `opts[:max_chunks]` chunks, empty
  ones included, by default `max_chunks/0`; either may be `:infinity`).
  """
  @spec assemble(Assembly.t(), map(), keyword()) ::
          {:more, Assembly.t()} | {:done, binary()} | {:error, atom()}
  def assemble(%Assembly{} = a, chunk, opts \\ []) do
    with %{"offset" => at, "bytes" => b64, "eof" => eof}
         when is_integer(at) and is_binary(b64) and is_boolean(eof) <- chunk,
         {:ok, bytes} <- unb64(b64) do
      limits =
        {Keyword.get(opts, :max_bytes, @max_bytes), Keyword.get(opts, :max_chunks, @max_chunks)}

      add(a, at, bytes, eof, limits)
    else
      _ -> {:error, :bad_chunk}
    end
  end

  defp add(a, at, bytes, eof, {max_bytes, max_chunks}) do
    next = a.offset + a.size
    size = a.size + byte_size(bytes)

    # (a number is less than any atom, so `:infinity` is no limit)
    cond do
      at < next and at + byte_size(bytes) <= next -> {:more, a}
      at != next -> {:error, :out_of_order}
      size > max_bytes or a.chunks + 1 > max_chunks -> {:error, :too_large}
      eof -> {:done, IO.iodata_to_binary(Enum.reverse([bytes | a.parts]))}
      true -> {:more, %{a | parts: [bytes | a.parts], size: size, chunks: a.chunks + 1}}
    end
  end

  # ── base64url ──

  @doc "Unpadded base64url, as every binary on the link travels."
  @spec b64(binary()) :: String.t()
  def b64(bytes), do: Base.url_encode64(bytes, padding: false)

  @doc "`b64/1` back: `{:ok, bytes}` or `:error`."
  @spec unb64(term()) :: {:ok, binary()} | :error
  def unb64(text) when is_binary(text), do: Base.url_decode64(text, padding: false)
  def unb64(_other), do: :error

  defp stringify(fields), do: Map.new(fields, fn {k, v} -> {to_string(k), v} end)
end
