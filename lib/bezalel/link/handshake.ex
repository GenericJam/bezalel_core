defmodule Bezalel.Link.Handshake do
  @moduledoc """
  The phone ↔ server link's handshake and sealing (`wss://<origin>/link/phone`),
  shared so both sides run one implementation. Pure: no sockets, no storage.
  The phone always dials; the server speaks first.

      S→P  hello  {op: "hello", v: 1, server_eph, nonce, server_key, sig}
      P→S  auth   {op: "auth", v: 1, device_key, phone_eph, app, platform, sig}
      then every frame both ways is sealed (`seal/2`, `open/2`)

  Keys and signatures travel as unpadded base64url. The signed transcripts
  and key derivation (each field length-prefixed, `t/2`):

    * `hello.sig` = Ed25519 by the server key over
      `t("bezalel-link-hello-v1", [server_eph, nonce])`
    * `auth.sig` = Ed25519 by the device key over
      `t("bezalel-link-auth-v1", [origin, nonce, server_eph, phone_eph,
      server_key, device_key, app, platform])`: the phone vouches for this
      server, this origin, this connection's keys and the labels it gives
      itself (`app`, `platform`: strings of at most 255 bytes each)
    * `shared` = X25519(an ephemeral key, the other's); `okm` =
      HKDF-SHA256(`shared`, salt `nonce`, info
      `t("bezalel-link-v1", [server_eph, phone_eph])`, 64 bytes): the first
      32 bytes seal phone→server, the last 32 server→phone

  `t(label, fields)` is `label <> <<0>>` then each field as
  `<<byte_size::16, field::binary>>`.

  A sealed frame is `<<counter::64, ciphertext::binary, tag::binary-16>>`,
  AES-256-GCM with IV `<<direction::8, 0::24, counter::64>>` (1 phone→server,
  2 server→phone) and AAD `"bezalel-link-v1"`. Each direction counts from 0
  and the receiver takes only the next count: a replayed, reordered or
  dropped frame is refused. A new connection is a new handshake with new
  ephemeral keys, so recorded traffic stays sealed (forward secrecy).

  The phone pins the server key per origin (from the QR code,
  `Bezalel.Link.Pairing`); a different one is `{:error, :key_changed}`.
  The account is the device key (`Bezalel.Link.Pairing.account_id/1`), so
  the server refuses a device key no one holds the private key of: one of
  Ed25519's 8 small-order points (a signature anyone can forge verifies
  under them) or a non-canonical encoding.
  """

  import Bitwise, only: [<<<: 2]

  alias Bezalel.Link.{Pairing, Wire}

  @version 1
  @hello "bezalel-link-hello-v1"
  @auth "bezalel-link-auth-v1"
  @info "bezalel-link-v1"
  @aad "bezalel-link-v1"
  @p2s 1
  @s2p 2
  @max_counter (1 <<< 64) - 1
  @max_label 255

  # Ed25519 point encodings with the sign bit cleared: y = 0, 1, p - 1 and
  # the two order-8 points' y. A device key whose y is one of these (either
  # sign), or not below p, is refused.
  @p (1 <<< 255) - 19
  @small_order [0, 1, @p - 1] ++
                 for(
                   hex <- [
                     "26e8958fc2b227b045c3f489f2ef98f0d5dfac05d3c63339b13802886d53fc05",
                     "c7176a703d4dd84fba3c0b760d10670f2a2053fa2c39ccc64ec7fd7792ac037a"
                   ],
                   do: :binary.decode_unsigned(Base.decode16!(hex, case: :lower), :little)
                 )

  @typedoc "An Ed25519 key pair, `{public, private}` (32 bytes each; the private one is the seed)."
  @type keypair :: {binary(), binary()}

  defmodule Session do
    @moduledoc "One connection's sealing state: keys and per-direction counters."
    @derive {Inspect, only: [:role, :sent, :received]}
    @enforce_keys [:role, :send_key, :recv_key]
    defstruct [:role, :send_key, :recv_key, sent: 0, received: 0]

    @type t :: %__MODULE__{
            role: :phone | :server,
            send_key: binary(),
            recv_key: binary(),
            sent: non_neg_integer(),
            received: non_neg_integer()
          }
  end

  defmodule Pending do
    @moduledoc "The server's side of a hello, until the phone's auth arrives."
    @derive {Inspect, only: []}
    @enforce_keys [:server_key, :eph, :nonce]
    defstruct [:server_key, :eph, :nonce]

    @type t :: %__MODULE__{server_key: binary(), eph: {binary(), binary()}, nonce: binary()}
  end

  @doc "A new Ed25519 key pair (a device key, the server's link key)."
  @spec keypair() :: keypair()
  def keypair, do: :crypto.generate_key(:eddsa, :ed25519)

  @doc "The key pair of a stored private key (the 32-byte seed)."
  @spec keypair(binary()) :: keypair()
  def keypair(<<_::binary-32>> = private), do: :crypto.generate_key(:eddsa, :ed25519, private)

  # ── server ──

  @doc """
  The server's first frame, and what it keeps until the phone answers.
  `opts` (tests): `:eph` (an X25519 private key), `:nonce` (32 bytes).
  """
  @spec hello(keypair(), keyword()) :: {map(), Pending.t()}
  def hello({server_pub, server_priv}, opts \\ []) do
    eph = x25519(opts[:eph])
    nonce = opts[:nonce] || :crypto.strong_rand_bytes(32)
    {eph_pub, _} = eph

    frame = %{
      "op" => "hello",
      "v" => @version,
      "server_eph" => Wire.b64(eph_pub),
      "nonce" => Wire.b64(nonce),
      "server_key" => Wire.b64(server_pub),
      "sig" => Wire.b64(sign(t(@hello, [eph_pub, nonce]), server_priv))
    }

    {frame, %Pending{server_key: server_pub, eph: eph, nonce: nonce}}
  end

  @doc """
  The server checks the phone's `auth` frame for `origin` (its own, as
  the phone dialled it): the device's signature over this connection's
  transcript, which covers the frame's `app` and `platform` too (so they
  can be shown as the phone gave them). `{:ok, session, device_key}`, or
  `{:error, reason}`: `:bad_frame` (also a small-order or non-canonical
  device key), `:unsupported_version`, `:bad_signature`, `:invalid_origin`.
  """
  @spec accept(Pending.t(), map(), String.t()) ::
          {:ok, Session.t(), binary()} | {:error, atom()}
  def accept(%Pending{} = p, frame, origin) when is_binary(origin) do
    {eph_pub, eph_priv} = p.eph

    with {:ok, origin} <- Pairing.canonical_origin(origin),
         {:ok, %{"device_key" => device, "phone_eph" => phone_eph, "sig" => sig} = f} <-
           fields(frame, "auth", device_key: 32, phone_eph: 32, sig: 64),
         app = f["app"],
         platform = f["platform"],
         true <- (label?(app) and label?(platform)) || {:error, :bad_frame},
         true <- device_key?(device) || {:error, :bad_frame},
         msg =
           t(@auth, [origin, p.nonce, eph_pub, phone_eph, p.server_key, device, app, platform]),
         true <- verify(msg, sig, device) || {:error, :bad_signature},
         {:ok, shared} <- x25519_shared(phone_eph, eph_priv) do
      {p2s, s2p} = derive(shared, p.nonce, eph_pub, phone_eph)
      {:ok, %Session{role: :server, send_key: s2p, recv_key: p2s}, device}
    end
  end

  # ── phone ──

  @doc """
  The phone answers the server's `hello`. Options: `:device_key` (the
  account's `t:keypair/0`), `:origin` (what it dialled), `:pinned` (the
  server key it pinned for that origin, or nil to take this one: the QR
  code's fingerprint is checked by `Bezalel.Link.Pairing`), `:app`,
  `:platform` (labels for the server's list of sessions, at most 255
  bytes each; signed with the rest); tests: `:eph`.
  `{:ok, auth_frame, session, server_key}`,
  or `{:error, reason}`: `:bad_frame`, `:unsupported_version`,
  `:key_changed`, `:bad_signature`, `:invalid_origin`.
  """
  @spec auth(map(), keyword()) :: {:ok, map(), Session.t(), binary()} | {:error, atom()}
  def auth(hello, opts) do
    {device_pub, device_priv} = Keyword.fetch!(opts, :device_key)
    origin = Keyword.fetch!(opts, :origin)
    pinned = opts[:pinned]
    app = label!(opts[:app])
    platform = label!(opts[:platform])

    with {:ok, origin} <- Pairing.canonical_origin(origin),
         {:ok, h} <- fields(hello, "hello", server_eph: 32, nonce: 32, server_key: 32, sig: 64),
         %{"server_eph" => server_eph, "nonce" => nonce, "server_key" => server_key} = h,
         true <- pinned in [nil, server_key] || {:error, :key_changed},
         true <-
           verify(t(@hello, [server_eph, nonce]), h["sig"], server_key) ||
             {:error, :bad_signature},
         {phone_eph, phone_priv} = x25519(opts[:eph]),
         {:ok, shared} <- x25519_shared(server_eph, phone_priv) do
      msg =
        t(@auth, [origin, nonce, server_eph, phone_eph, server_key, device_pub, app, platform])

      frame = %{
        "op" => "auth",
        "v" => @version,
        "device_key" => Wire.b64(device_pub),
        "phone_eph" => Wire.b64(phone_eph),
        "app" => app,
        "platform" => platform,
        "sig" => Wire.b64(sign(msg, device_priv))
      }

      {p2s, s2p} = derive(shared, nonce, server_eph, phone_eph)
      {:ok, frame, %Session{role: :phone, send_key: p2s, recv_key: s2p}, server_key}
    end
  end

  # ── sealing ──

  @doc "Seals `plaintext` (a `Bezalel.Link.Wire` frame's JSON) for the other side."
  @spec seal(Session.t(), iodata()) :: {binary(), Session.t()}
  def seal(%Session{sent: n} = s, plaintext) when n < @max_counter do
    {ct, tag} =
      :crypto.crypto_one_time_aead(
        :aes_256_gcm,
        s.send_key,
        iv(direction(s.role, :send), n),
        plaintext,
        @aad,
        true
      )

    {<<n::64, ct::binary, tag::binary>>, %{s | sent: n + 1}}
  end

  @doc """
  Opens a frame the other side sealed: `{:ok, plaintext, session}`, or
  `{:error, reason}`: `:replayed` (a count already taken), `:out_of_order`
  (a later one: a frame was lost or held back), `:tampered` (it doesn't
  open), `:bad_frame`.
  """
  @spec open(Session.t(), binary()) :: {:ok, binary(), Session.t()} | {:error, atom()}
  def open(%Session{received: expected} = s, <<n::64, rest::binary>>)
      when byte_size(rest) >= 16 do
    cond do
      n < expected ->
        {:error, :replayed}

      n > expected ->
        {:error, :out_of_order}

      true ->
        ct_size = byte_size(rest) - 16
        <<ct::binary-size(^ct_size), tag::binary-16>> = rest
        iv = iv(direction(s.role, :receive), n)

        case :crypto.crypto_one_time_aead(:aes_256_gcm, s.recv_key, iv, ct, @aad, tag, false) do
          plaintext when is_binary(plaintext) -> {:ok, plaintext, %{s | received: n + 1}}
          :error -> {:error, :tampered}
        end
    end
  end

  def open(%Session{}, _frame), do: {:error, :bad_frame}

  # ── the parts (public for the known-answer tests) ──

  @doc false
  @spec t(String.t(), [binary()]) :: binary()
  def t(label, fields),
    do: IO.iodata_to_binary([label, 0 | Enum.map(fields, &[<<byte_size(&1)::16>>, &1])])

  @doc false
  # `{phone→server key, server→phone key}`.
  @spec derive(binary(), binary(), binary(), binary()) :: {binary(), binary()}
  def derive(shared, nonce, server_eph, phone_eph) do
    <<p2s::binary-32, s2p::binary-32>> =
      hkdf(shared, nonce, t(@info, [server_eph, phone_eph]), 64)

    {p2s, s2p}
  end

  @doc false
  # RFC 5869 HKDF with SHA-256.
  @spec hkdf(binary(), binary(), binary(), pos_integer()) :: binary()
  def hkdf(ikm, salt, info, length) do
    prk = :crypto.mac(:hmac, :sha256, salt, ikm)

    {okm, _} =
      Enum.reduce(1..ceil(length / 32)//1, {"", ""}, fn i, {acc, prev} ->
        block = :crypto.mac(:hmac, :sha256, prk, [prev, info, i])
        {acc <> block, block}
      end)

    binary_part(okm, 0, length)
  end

  defp iv(direction, n), do: <<direction::8, 0::24, n::64>>

  defp direction(:phone, :send), do: @p2s
  defp direction(:phone, :receive), do: @s2p
  defp direction(:server, :send), do: @s2p
  defp direction(:server, :receive), do: @p2s

  defp sign(msg, private), do: :crypto.sign(:eddsa, :none, msg, [private, :ed25519])

  defp verify(msg, sig, public),
    do: :crypto.verify(:eddsa, :none, msg, sig, [public, :ed25519])

  # A canonical encoding of a point that isn't of small order.
  defp device_key?(key) do
    y = key |> :binary.decode_unsigned(:little) |> Bitwise.band((1 <<< 255) - 1)
    y < @p and y not in @small_order
  end

  # `app` and `platform`: strings short enough to show (and to length-prefix).
  defp label?(text), do: is_binary(text) and byte_size(text) <= @max_label

  defp label!(value) do
    text = to_string(value || "")

    if byte_size(text) <= @max_label,
      do: text,
      else: raise(ArgumentError, "an auth label is at most #{@max_label} bytes")
  end

  defp x25519(nil), do: :crypto.generate_key(:ecdh, :x25519)
  defp x25519(private), do: :crypto.generate_key(:ecdh, :x25519, private)

  # An all-zero result means a low-order public key: refused.
  defp x25519_shared(public, private) do
    case :crypto.compute_key(:ecdh, public, private, :x25519) do
      <<0::256>> -> {:error, :bad_frame}
      shared -> {:ok, shared}
    end
  rescue
    ErlangError -> {:error, :bad_frame}
  end

  # The frame's op and version, and each binary field decoded to its size.
  defp fields(%{"op" => op, "v" => @version} = frame, op, sizes) do
    Enum.reduce_while(sizes, {:ok, frame}, fn {key, size}, {:ok, acc} ->
      key = Atom.to_string(key)

      case Wire.unb64(frame[key]) do
        {:ok, <<_::binary-size(^size)>> = bin} -> {:cont, {:ok, Map.put(acc, key, bin)}}
        _ -> {:halt, {:error, :bad_frame}}
      end
    end)
  end

  defp fields(%{"op" => op, "v" => _other}, op, _sizes), do: {:error, :unsupported_version}
  defp fields(_frame, _op, _sizes), do: {:error, :bad_frame}
end
