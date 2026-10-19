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

  @doc "A new offer: `{pair_id, secret}` (16 and 32 random bytes)."
  @spec offer() :: {binary(), binary()}
  def offer, do: {:crypto.strong_rand_bytes(16), :crypto.strong_rand_bytes(32)}

  @doc "The QR code's text for an offer of `origin` (`\"https://…\"`), server key `server_key`."
  @spec qr(String.t(), binary(), binary(), binary()) :: String.t()
  def qr(origin, pair_id, secret, server_key) do
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
  A scanned QR code's offer: `{:ok, %{origin, pair_id, secret,
  server_fingerprint}}`, or `{:error, :not_a_link}` for anything else
  (another app's code, a link that isn't https).
  """
  @spec parse_qr(String.t()) ::
          {:ok,
           %{
             origin: String.t(),
             pair_id: binary(),
             secret: binary(),
             server_fingerprint: String.t()
           }}
          | {:error, :not_a_link}
  def parse_qr(text) when is_binary(text) do
    with %URI{scheme: "bezalel", host: "link", query: query} when is_binary(query) <-
           URI.parse(String.trim(text)),
         %{"o" => origin, "p" => p, "s" => s, "k" => k} <- URI.decode_query(query),
         %URI{scheme: "https", host: host} when host not in [nil, ""] <- URI.parse(origin),
         {:ok, <<_::binary-16>> = pair_id} <- Wire.unb64(p),
         {:ok, <<_::binary-32>> = secret} <- Wire.unb64(s),
         {:ok, <<_::binary-32>>} <- Wire.unb64(k) do
      {:ok, %{origin: origin, pair_id: pair_id, secret: secret, server_fingerprint: k}}
    else
      _ -> {:error, :not_a_link}
    end
  end

  @doc "The server key's fingerprint in the QR code: its SHA-256, base64url."
  @spec server_fingerprint(binary()) :: String.t()
  def server_fingerprint(server_key), do: Wire.b64(:crypto.hash(:sha256, server_key))

  @doc "Does the handshake's `server_key` match the QR code's fingerprint?"
  @spec server_key?(binary(), String.t()) :: boolean()
  def server_key?(server_key, fingerprint) when is_binary(fingerprint) do
    expected = server_fingerprint(server_key)
    byte_size(fingerprint) == byte_size(expected) and :crypto.hash_equals(expected, fingerprint)
  end

  @doc "The phone's proof that it scanned the offer: HMAC-SHA256 of the offer and its device key."
  @spec claim_proof(binary(), binary(), binary()) :: binary()
  def claim_proof(secret, pair_id, device_key),
    do: :crypto.mac(:hmac, :sha256, secret, Handshake.t(@claim, [pair_id, device_key]))

  @doc "Is `proof` the claim of the device `device_key` on this offer? (Constant time.)"
  @spec valid_claim?(binary(), binary(), binary(), binary()) :: boolean()
  def valid_claim?(secret, pair_id, device_key, proof) when is_binary(proof) do
    expected = claim_proof(secret, pair_id, device_key)
    byte_size(proof) == byte_size(expected) and :crypto.hash_equals(expected, proof)
  end

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
