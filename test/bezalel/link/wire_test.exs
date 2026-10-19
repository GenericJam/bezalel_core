defmodule Bezalel.Link.WireTest do
  use ExUnit.Case, async: true

  alias Bezalel.Link.{Handshake, Pairing, Wire}

  describe "frames" do
    test "a request and its answer round-trip as JSON" do
      request = Wire.frame("conv.pull", %{uid: "u1", from: 0}, "7")
      assert {:ok, decoded} = request |> Wire.encode() |> Wire.decode()
      assert decoded == %{"op" => "conv.pull", "id" => "7", "uid" => "u1", "from" => 0}

      assert Wire.reply(decoded, "ack", %{size: 10}) == %{
               "op" => "ack",
               "re" => "7",
               "size" => 10
             }

      assert Wire.error(decoded, "unknown_op") ==
               %{"op" => "error", "re" => "7", "code" => "unknown_op", "message" => ""}
    end

    test "what isn't a frame is refused" do
      assert Wire.decode("not json") == {:error, :not_json}
      assert Wire.decode(~s({"id":1})) == {:error, :no_op}
      assert Wire.decode(~s([1])) == {:error, :no_op}
      assert Wire.decode(String.duplicate(" ", Wire.max_frame() + 1)) == {:error, :too_large}

      for other <- [nil, 1, %{"op" => "ack"}, [~s({"op":"ack"})]] do
        assert Wire.decode(other) == {:error, :not_json}
      end

      assert Wire.known_op?("cred.rotated")
      refute Wire.known_op?("shell.exec")
    end

    test "a full window of chunks, base64'd and sealed, stays under the frame limit" do
      [chunk | _] = Wire.chunks(:crypto.strong_rand_bytes(Wire.chunk_size()))
      json = Wire.encode(Wire.frame("conv.data", Map.put(chunk, "uid", "u1"), "1"))
      %{phone: phone} = link()
      {sealed, _} = Handshake.seal(phone, json)
      assert byte_size(sealed) < Wire.max_frame()
    end
  end

  describe "chunks" do
    test "bytes split and put back together, from an offset" do
      bytes = :crypto.strong_rand_bytes(10_000)
      chunks = Wire.chunks(bytes, 500, chunk_size: 3000)

      assert Enum.map(chunks, &{&1["offset"], &1["eof"]}) ==
               [{500, false}, {3500, false}, {6500, false}, {9500, true}]

      assert {:done, ^bytes} =
               Enum.reduce(chunks, {:more, Wire.assembly(500)}, fn c, {:more, a} ->
                 Wire.assemble(a, c)
               end)

      assert Wire.chunks("", 42) == [%{"offset" => 42, "bytes" => "", "eof" => true}]
      assert {:done, ""} = Wire.assemble(Wire.assembly(42), hd(Wire.chunks("", 42)))
    end

    test "a resent chunk is ignored; a gap, a bad chunk or too many bytes are errors" do
      [c0, c1, c2] = Wire.chunks(:crypto.strong_rand_bytes(25), 0, chunk_size: 10)
      {:more, a} = Wire.assemble(Wire.assembly(), c0)

      assert Wire.assemble(a, c0) == {:more, a}
      assert Wire.assemble(a, c2) == {:error, :out_of_order}
      assert Wire.assemble(a, %{c1 | "bytes" => "!!"}) == {:error, :bad_chunk}
      assert Wire.assemble(a, Map.delete(c1, "eof")) == {:error, :bad_chunk}
      assert Wire.assemble(a, c1, max_bytes: 15) == {:error, :too_large}
      assert Wire.assemble(a, c1, max_chunks: 1) == {:error, :too_large}
    end

    test "an assembly is bounded by default; no limit only when asked" do
      # one byte past the default size (the assembly only counts what it holds)
      full = %{Wire.assembly() | size: Wire.max_bytes()}
      one_more = %{"offset" => Wire.max_bytes(), "bytes" => Wire.b64("x"), "eof" => false}
      assert Wire.assemble(full, one_more) == {:error, :too_large}
      assert {:more, _} = Wire.assemble(full, one_more, max_bytes: :infinity)

      # empty chunks that never end count towards the chunk limit
      empty = %{"offset" => 0, "bytes" => "", "eof" => false}

      result =
        Enum.reduce_while(1..(Wire.max_chunks() + 1), Wire.assembly(), fn _, a ->
          case Wire.assemble(a, empty) do
            {:more, a} -> {:cont, a}
            other -> {:halt, {other, a.chunks}}
          end
        end)

      assert result == {{:error, :too_large}, Wire.max_chunks()}

      many = %{Wire.assembly() | chunks: Wire.max_chunks()}
      assert {:more, _} = Wire.assemble(many, empty, max_chunks: :infinity)
    end
  end

  describe "pairing" do
    test "the QR code carries the offer and the server key's fingerprint, and reads back" do
      {pair_id, secret} = Pairing.offer()
      {server_key, _} = Handshake.keypair()
      qr = Pairing.qr("https://study.genericjam.com", pair_id, secret, server_key)

      assert String.starts_with?(qr, "bezalel://link?o=https%3A%2F%2Fstudy.genericjam.com&p=")
      assert byte_size(qr) < 200

      assert {:ok, offer} = Pairing.parse_qr(qr)
      assert offer.origin == "https://study.genericjam.com"
      assert {offer.pair_id, offer.secret} == {pair_id, secret}
      assert Pairing.server_key?(server_key, offer.server_fingerprint)
      refute Pairing.server_key?(elem(Handshake.keypair(), 0), offer.server_fingerprint)
      refute Pairing.server_key?(server_key, "short")
      refute Pairing.server_key?(server_key, nil)
      refute Pairing.server_key?(nil, offer.server_fingerprint)
    end

    test "anything else scanned is not a link" do
      {pair_id, secret} = Pairing.offer()
      {server_key, _} = Handshake.keypair()

      for text <- [
            "https://example.com",
            "bezalel://other?o=x",
            Pairing.qr("http://study.genericjam.com", pair_id, secret, server_key),
            Pairing.qr("https://study.genericjam.com", "short", secret, server_key),
            "bezalel://link?o=https%3A%2F%2Fa.b&p=x",
            "bezalel://link?o=%zz&p=x",
            <<0xFF, 0xFE>>,
            nil,
            42
          ] do
        assert Pairing.parse_qr(text) == {:error, :not_a_link}, inspect(text)
      end
    end

    test "a claim proves the secret for this offer and this device only" do
      {pair_id, secret} = Pairing.offer()
      {device, _} = Handshake.keypair()
      proof = Pairing.claim_proof(secret, pair_id, device)

      assert Pairing.valid_claim?(secret, pair_id, device, proof)
      refute Pairing.valid_claim?(secret, pair_id, elem(Handshake.keypair(), 0), proof)
      refute Pairing.valid_claim?(secret, elem(Pairing.offer(), 0), device, proof)
      refute Pairing.valid_claim?(elem(Pairing.offer(), 1), pair_id, device, proof)
      refute Pairing.valid_claim?(secret, pair_id, device, "short")

      # a field missing from the claim frame, or not a string
      for args <- [
            [secret, pair_id, device, nil],
            [secret, pair_id, nil, proof],
            [secret, nil, device, proof],
            [nil, pair_id, device, proof],
            [secret, pair_id, device, 1]
          ] do
        refute apply(Pairing, :valid_claim?, args)
      end
    end

    test "the account and its fingerprint come from the device key" do
      device =
        Base.decode16!("8139770ea87d175f56a35466c34c7ecccb8d8a91b4ee37a25df60f5b8fc9b394",
          case: :lower
        )

      hash = Base.encode32(:crypto.hash(:sha256, device), padding: false)

      assert Pairing.account_id(device) == "acct_" <> String.downcase(binary_part(hash, 0, 26))
      assert Pairing.fingerprint(device) =~ ~r/^[A-Z2-7]{4}-[A-Z2-7]{4}$/
      assert String.replace(Pairing.fingerprint(device), "-", "") == binary_part(hash, 0, 8)
    end
  end

  defp link do
    {hello, pending} = Handshake.hello(Handshake.keypair())

    {:ok, auth, phone, _} =
      Handshake.auth(hello, device_key: Handshake.keypair(), origin: "https://a.example")

    {:ok, server, _} = Handshake.accept(pending, auth, "https://a.example")
    %{phone: phone, server: server}
  end
end
