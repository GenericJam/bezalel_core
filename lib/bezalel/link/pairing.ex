defmodule Bezalel.Link.Pairing do
  @moduledoc """
  What the phone and the website must agree on to link a browser by QR
  code, WhatsApp-style, and to name the account:

    * the QR code, `bezalel://link?o=ORIGIN&p=PAIR_ID&s=SECRET&k=SERVER_FP`
      (`qr/4`, `parse_qr/1`): the website's origin, a one-time offer id
      (16 random bytes) and secret (32), and the fingerprint of the
      server's link key (`server_fingerprint/1`), which the phone pins for
      that origin and checks against the handshake's `server_key`
    * the claim (`pair.claim`): the phone never sends the secret, only
      `claim_proof/3`, an HMAC binding it to the offer and the phone's
      device key, so a logged or replayed claim is worthless
    * the account: `account_id/1` and the `fingerprint/1` people compare,
      both from the device key (the account is the phone's key)
  """

  alias Bezalel.Link.Handshake
  alias Bezalel.Link.Wire

  @claim "bezalel-link-claim-v1"
  @idna_dot_separators ["。", "．", "｡"]
  @qr_fields ~w(k o p s)

  @doc "A new offer: `{pair_id, secret}` (16 and 32 random bytes)."
  @spec offer() :: {binary(), binary()}
  def offer, do: {:crypto.strong_rand_bytes(16), :crypto.strong_rand_bytes(32)}

  @doc """
  The QR code's text for an offer of `origin` (`"https://…"`), server key
  `server_key`. Raises `ArgumentError` when the origin is invalid.
  """
  @spec qr(String.t(), binary(), binary(), binary()) :: String.t()
  def qr(origin, pair_id, secret, server_key) do
    origin =
      case canonical_origin(origin) do
        {:ok, canonical} -> canonical
        {:error, :invalid_origin} -> raise ArgumentError, "invalid HTTPS origin"
      end

    query =
      URI.encode_query(
        [
          {"o", origin},
          {"p", Wire.b64(pair_id)},
          {"s", Wire.b64(secret)},
          {"k", server_fingerprint(server_key)}
        ],
        :rfc3986
      )

    "bezalel://link?" <> query
  end

  @doc """
  Validates and canonicalizes a link origin.

  Public origins require HTTPS. Plain HTTP is accepted only for the
  loopback hosts used by local development and tests. The result has an
  ASCII DNS name (IDNA and lowercase), at most one terminal DNS dot
  removed, no path or trailing slash, and no default port. A valid
  non-default port is retained. IPv4 must already use canonical dotted
  decimal; bracketed IPv6 is serialized in its canonical form.
  """
  @spec canonical_origin(term()) :: {:ok, String.t()} | {:error, :invalid_origin}
  def canonical_origin(origin) when is_binary(origin) do
    with true <- String.valid?(origin),
         false <- control_character?(origin),
         {:ok, scheme, authority} <- origin_authority(origin),
         {:ok, host, port} <- authority_parts(authority),
         {:ok, host} <- canonical_host(host),
         true <- scheme == "https" or loopback?(host),
         {:ok, port} <- canonical_port(port, scheme) do
      {:ok, scheme <> "://" <> host <> port}
    else
      _ -> {:error, :invalid_origin}
    end
  rescue
    _ -> {:error, :invalid_origin}
  catch
    :exit, _ -> {:error, :invalid_origin}
  end

  def canonical_origin(_origin), do: {:error, :invalid_origin}

  @doc """
  A scanned QR code's offer: `{:ok, %{origin, pair_id, secret,
  server_fingerprint}}`, or `{:error, :not_a_link}` for anything else
  (another app's code, a disallowed origin, a malformed one, not a
  string).
  """
  @spec parse_qr(term()) ::
          {:ok,
           %{
             origin: String.t(),
             pair_id: binary(),
             secret: binary(),
             server_fingerprint: String.t()
           }}
          | {:error, :not_a_link}
  def parse_qr(text) when is_binary(text) do
    with true <- String.valid?(text),
         false <- control_character?(text),
         {:ok, query} <- link_query(text),
         {:ok, %{"o" => origin, "p" => p, "s" => s, "k" => k}} <- query_fields(query),
         {:ok, origin} <- canonical_origin(origin),
         {:ok, <<_::binary-16>> = pair_id} <- Wire.unb64(p),
         {:ok, <<_::binary-32>> = secret} <- Wire.unb64(s),
         {:ok, <<_::binary-32>>} <- Wire.unb64(k) do
      {:ok, %{origin: origin, pair_id: pair_id, secret: secret, server_fingerprint: k}}
    else
      _ -> {:error, :not_a_link}
    end
  rescue
    _ -> {:error, :not_a_link}
  catch
    :exit, _ -> {:error, :not_a_link}
  end

  def parse_qr(_other), do: {:error, :not_a_link}

  defp origin_authority(<<scheme::binary-size(5), "://", rest::binary>>) do
    authority(scheme, rest, "https")
  end

  defp origin_authority(<<scheme::binary-size(4), "://", rest::binary>>) do
    authority(scheme, rest, "http")
  end

  defp origin_authority(_origin), do: :error

  defp authority(scheme, rest, expected) do
    if String.downcase(scheme) == expected and not String.contains?(rest, ["?", "#"]) do
      case String.split(rest, "/", parts: 2) do
        [authority] when authority != "" -> {:ok, expected, authority}
        [authority, ""] when authority != "" -> {:ok, expected, authority}
        _ -> :error
      end
    else
      :error
    end
  end

  defp authority_parts(authority) do
    if String.contains?(authority, ["@", "%", "\\"]) do
      :error
    else
      split_host_port(authority)
    end
  end

  defp split_host_port("[" <> rest) do
    case String.split(rest, "]", parts: 2) do
      [address, suffix] when address != "" ->
        case port_suffix(suffix) do
          {:ok, port} -> {:ok, {:ipv6, address}, port}
          :error -> :error
        end

      _ ->
        :error
    end
  end

  defp split_host_port(authority) do
    if String.contains?(authority, ["[", "]"]) do
      :error
    else
      case String.split(authority, ":", parts: 2) do
        [host] when host != "" -> {:ok, {:name, host}, nil}
        [host, port] when host != "" -> {:ok, {:name, host}, port}
        _ -> :error
      end
    end
  end

  defp port_suffix(""), do: {:ok, nil}
  defp port_suffix(":" <> port), do: {:ok, port}
  defp port_suffix(_suffix), do: :error

  defp canonical_host({:ipv6, address}) do
    case :inet.parse_ipv6_address(String.to_charlist(address)) do
      {:ok, parsed} -> {:ok, "[" <> ipv6_text(parsed) <> "]"}
      {:error, _reason} -> :error
    end
  end

  defp canonical_host({:name, host}) do
    host = normalize_dot_separators(host)

    with {:ok, host, terminal_dot?} <- strip_terminal_dot(host),
         true <- valid_source_labels?(host),
         ascii <- host |> String.to_charlist() |> :idna.encode([:uts46, :std3_rules]),
         ascii <- ascii |> List.to_string() |> String.downcase(),
         true <- valid_ascii_hostname?(ascii) do
      canonical_name_or_ipv4(host, ascii, terminal_dot?)
    else
      _ -> :error
    end
  end

  # RFC 5952's lowercase hex and longest (first on ties) zero run. Avoid
  # :inet.ntoa/1's version-dependent dotted-quad spelling for mapped IPv4.
  defp ipv6_text(parsed) do
    groups = Tuple.to_list(parsed)
    {start, count} = longest_zero_run(groups)

    text =
      if count >= 2 do
        left = groups |> Enum.take(start) |> Enum.map_join(":", &Integer.to_string(&1, 16))

        right =
          groups |> Enum.drop(start + count) |> Enum.map_join(":", &Integer.to_string(&1, 16))

        left <> "::" <> right
      else
        Enum.map_join(groups, ":", &Integer.to_string(&1, 16))
      end

    String.downcase(text)
  end

  defp longest_zero_run(groups) do
    {best, current} =
      groups
      |> Enum.with_index()
      |> Enum.reduce({{0, 0}, nil}, fn
        {0, index}, {best, nil} -> {best, {index, 1}}
        {0, _index}, {best, {start, count}} -> {best, {start, count + 1}}
        {_nonzero, _index}, {best, current} -> {longer_run(best, current), nil}
      end)

    longer_run(best, current)
  end

  defp longer_run(best, nil), do: best

  defp longer_run({_start, length}, {_other_start, count} = candidate) when count > length,
    do: candidate

  defp longer_run(best, _candidate), do: best

  defp normalize_dot_separators(host) do
    Enum.reduce(@idna_dot_separators, host, &String.replace(&2, &1, "."))
  end

  defp strip_terminal_dot(host) do
    if String.ends_with?(host, ".") do
      stripped = binary_part(host, 0, byte_size(host) - 1)

      if stripped != "" and not String.ends_with?(stripped, "."),
        do: {:ok, stripped, true},
        else: :error
    else
      {:ok, host, false}
    end
  end

  defp valid_source_labels?(host) do
    host != "" and
      host
      |> String.split(".", trim: false)
      |> Enum.all?(&(&1 != ""))
  end

  defp valid_ascii_hostname?(host) do
    byte_size(host) <= 253 and
      host
      |> String.split(".", trim: false)
      |> Enum.all?(&(byte_size(&1) in 1..63))
  end

  defp canonical_name_or_ipv4(source, ascii, terminal_dot?) do
    cond do
      numeric_hostname?(ascii) -> canonical_ipv4(source, ascii, terminal_dot?)
      ipv4_number_label?(ascii) -> :error
      true -> {:ok, ascii}
    end
  end

  defp canonical_ipv4(source, ascii, terminal_dot?) do
    case :inet.parse_ipv4_address(String.to_charlist(ascii)) do
      {:ok, address} ->
        canonical = List.to_string(:inet.ntoa(address))

        if source == canonical and ascii == canonical and not terminal_dot?,
          do: {:ok, canonical},
          else: :error

      {:error, _reason} ->
        :error
    end
  end

  defp ipv4_number_label?(host) do
    last = host |> String.split(".") |> List.last()

    ascii_digits?(last) or
      case String.downcase(last) do
        "0x" <> hex -> hex == "" or hex_string?(hex)
        _ -> false
      end
  end

  defp hex_string?(text) do
    text
    |> :binary.bin_to_list()
    |> Enum.all?(fn character ->
      character in ?0..?9 or character in ?a..?f
    end)
  end

  defp numeric_hostname?(host) do
    host
    |> :binary.bin_to_list()
    |> Enum.all?(fn character -> character == ?. or character in ?0..?9 end)
  end

  defp canonical_port(nil, _scheme), do: {:ok, ""}

  defp canonical_port(port, scheme) do
    with true <- port != "" and ascii_digits?(port),
         {number, ""} <- Integer.parse(port),
         true <- number in 1..65_535,
         true <- Integer.to_string(number) == port do
      default = if scheme == "https", do: 443, else: 80
      if number == default, do: {:ok, ""}, else: {:ok, ":" <> port}
    else
      _ -> :error
    end
  end

  defp loopback?("localhost"), do: true
  defp loopback?("127.0.0.1"), do: true
  defp loopback?("[::1]"), do: true
  defp loopback?(_host), do: false

  defp ascii_digits?(text) do
    text
    |> :binary.bin_to_list()
    |> Enum.all?(&(&1 in ?0..?9))
  end

  defp link_query(text) do
    case URI.parse(text) do
      %URI{
        scheme: "bezalel",
        authority: "link",
        userinfo: nil,
        host: "link",
        port: nil,
        path: nil,
        query: query,
        fragment: nil
      }
      when is_binary(query) ->
        {:ok, query}

      _ ->
        :error
    end
  end

  defp query_fields(query) do
    segments = String.split(query, "&", trim: false)

    if Enum.all?(segments, &(&1 != "")) do
      fields = Enum.to_list(URI.query_decoder(query, :rfc3986))
      names = fields |> Enum.map(&elem(&1, 0)) |> Enum.sort()

      if names == @qr_fields, do: {:ok, Map.new(fields)}, else: :error
    else
      :error
    end
  end

  defp control_character?(text) do
    text
    |> String.to_charlist()
    |> Enum.any?(fn character -> character in 0..31 or character in 127..159 end)
  end

  @doc "The server key's fingerprint in the QR code: its SHA-256, base64url."
  @spec server_fingerprint(binary()) :: String.t()
  def server_fingerprint(server_key), do: Wire.b64(:crypto.hash(:sha256, server_key))

  @doc "Does the handshake's `server_key` match the QR code's fingerprint? (False for non-binaries.)"
  @spec server_key?(term(), term()) :: boolean()
  def server_key?(server_key, fingerprint)
      when is_binary(server_key) and is_binary(fingerprint) do
    expected = server_fingerprint(server_key)
    byte_size(fingerprint) == byte_size(expected) and :crypto.hash_equals(expected, fingerprint)
  end

  def server_key?(_server_key, _fingerprint), do: false

  @doc "The phone's proof that it scanned the offer: HMAC-SHA256 of the offer and its device key."
  @spec claim_proof(binary(), binary(), binary()) :: binary()
  def claim_proof(secret, pair_id, device_key),
    do: :crypto.mac(:hmac, :sha256, secret, Handshake.t(@claim, [pair_id, device_key]))

  @doc """
  Is `proof` the claim of the device `device_key` on this offer? (Constant
  time; false when any of them isn't a binary, a proof missing from a
  frame, say.)
  """
  @spec valid_claim?(term(), term(), term(), term()) :: boolean()
  def valid_claim?(secret, pair_id, device_key, proof)
      when is_binary(secret) and is_binary(pair_id) and is_binary(device_key) and
             is_binary(proof) do
    expected = claim_proof(secret, pair_id, device_key)
    byte_size(proof) == byte_size(expected) and :crypto.hash_equals(expected, proof)
  end

  def valid_claim?(_secret, _pair_id, _device_key, _proof), do: false

  @doc """
  The account a device key is: `"acct_"` and the first 26 characters of
  its SHA-256 in lowercase base32. Never typed by anyone.
  """
  @spec account_id(binary()) :: String.t()
  def account_id(device_key),
    do: "acct_" <> String.downcase(binary_part(base32(device_key), 0, 26))

  @doc "What people compare on the phone and in logs: `\"ABCD-EFGH\"`, the hash's first 8 base32 characters."
  @spec fingerprint(binary()) :: String.t()
  def fingerprint(device_key) do
    <<a::binary-4, b::binary-4, _::binary>> = base32(device_key)
    a <> "-" <> b
  end

  defp base32(key), do: Base.encode32(:crypto.hash(:sha256, key), padding: false)
end
