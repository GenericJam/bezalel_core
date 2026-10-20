defmodule Bezalel.Link.HandshakeTest do
  use ExUnit.Case, async: true

  alias Bezalel.Link.{Handshake, Pairing, Wire}

  @origin "https://study.genericjam.com"

  # Fixed keys; the expected values come from an independent
  # implementation of the moduledoc's spec (Python `cryptography`:
  # Ed25519, X25519, HKDF, AESGCM), not from this module.
  @server_seed :binary.copy(<<1>>, 32)
  @device_seed :binary.copy(<<2>>, 32)
  @server_eph :binary.copy(<<3>>, 32)
  @phone_eph :binary.copy(<<4>>, 32)
  @nonce :binary.copy(<<5>>, 32)

  @kat %{
    server_pub: "8a88e3dd7409f195fd52db2d3cba5d72ca6709bf1d94121bf3748801b40f6f5c",
    device_pub: "8139770ea87d175f56a35466c34c7ecccb8d8a91b4ee37a25df60f5b8fc9b394",
    s_eph_pub: "5dfedd3b6bd47f6fa28ee15d969d5bb0ea53774d488bdaf9df1c6e0124b3ef22",
    p_eph_pub: "ac01b2209e86354fb853237b5de0f4fab13c7fcbf433a61c019369617fecf10b",
    hello_sig:
      "e8b0652eada6b33ed39d7f95dae27238d4ceaf9889f7a07757e298e4c93dc5f1" <>
        "a6f6c5de88c09258f061578608fba7c96ad257bc3cb8d0f830409f4ec8974201",
    auth_sig:
      "d2558160d88691d58a79faef1e6d8fc56c35e6d06f8ff33a821c8a9b0a7102a6" <>
        "da260ff07be508c8244a6c41f2b1d35ad75c98ecd58de618e39b6caa5f86f305",
    p2s: "dce7db39640d4b4170b3bf09a1ac902c3556da2bebb1f12deeb0105d0bbfd7fe",
    s2p: "eb797d0f67a0685b93f1a0f461d8c58721c4e34dc5f68c0678c322abe4a716bd",
    frame_p0: "0000000000000000ed9be0fcf2af40e70a9047edfb0f7ad73eea97f61aac57800f8c51d0d5",
    frame_s1: "00000000000000015f3757be12f470b97b1d01fac35dd695f00c9c71461cd24753d6591c78",
    claim: "a89a99d2797766dc9eafcaef097f803f0e382c800f818fdc15887e233794a77b"
  }

  defp hex(name), do: Base.decode16!(@kat[name], case: :lower)
  defp unb64!(text), do: elem(Wire.unb64(text), 1)

  defp fixed do
    server = Handshake.keypair(@server_seed)
    device = Handshake.keypair(@device_seed)
    {hello, pending} = Handshake.hello(server, eph: @server_eph, nonce: @nonce)

    {:ok, auth, phone, server_key} =
      Handshake.auth(hello,
        device_key: device,
        origin: @origin,
        pinned: nil,
        app: "1.0",
        platform: "ios",
        eph: @phone_eph
      )

    {:ok, srv, device_key} = Handshake.accept(pending, auth, @origin)

    %{
      hello: hello,
      auth: auth,
      phone: phone,
      server: srv,
      server_key: server_key,
      device_key: device_key
    }
  end

  # A fresh, random handshake.
  defp linked do
    server = Handshake.keypair()
    device = Handshake.keypair()
    {hello, pending} = Handshake.hello(server)
    {:ok, auth, phone, _} = Handshake.auth(hello, device_key: device, origin: @origin)
    {:ok, srv, _} = Handshake.accept(pending, auth, @origin)

    %{
      phone: phone,
      server: srv,
      hello: hello,
      auth: auth,
      pending: pending,
      server_pub: elem(server, 0)
    }
  end

  describe "known answers (an independent implementation of the spec)" do
    test "keys, both signatures, the derived keys and sealed frames" do
      k = fixed()
      assert unb64!(k.hello["server_key"]) == hex(:server_pub)
      assert unb64!(k.hello["server_eph"]) == hex(:s_eph_pub)
      assert unb64!(k.hello["sig"]) == hex(:hello_sig)
      assert unb64!(k.auth["device_key"]) == hex(:device_pub)
      assert unb64!(k.auth["phone_eph"]) == hex(:p_eph_pub)
      assert unb64!(k.auth["sig"]) == hex(:auth_sig)
      assert k.server_key == hex(:server_pub)
      assert k.device_key == hex(:device_pub)

      assert {k.phone.send_key, k.phone.recv_key} == {hex(:p2s), hex(:s2p)}
      assert {k.server.recv_key, k.server.send_key} == {hex(:p2s), hex(:s2p)}

      ping = ~s({"op":"ping"})
      {frame, _} = Handshake.seal(k.phone, ping)
      assert frame == hex(:frame_p0)

      {_, server} = Handshake.seal(k.server, "first")
      {frame, _} = Handshake.seal(server, ping)
      assert frame == hex(:frame_s1)
    end

    test "the claim proof" do
      assert Pairing.claim_proof(
               :binary.copy(<<6>>, 32),
               :binary.copy(<<7>>, 16),
               hex(:device_pub)
             ) ==
               hex(:claim)
    end

    test "HKDF-SHA256 matches RFC 5869's test case 1" do
      ikm = :binary.copy(<<0x0B>>, 22)
      salt = Base.decode16!("000102030405060708090A0B0C")
      info = Base.decode16!("F0F1F2F3F4F5F6F7F8F9")

      assert Handshake.hkdf(ikm, salt, info, 42) ==
               Base.decode16!(
                 "3CB25F25FAACD57A90434F64D0362F2A2D2D0A90CF1A5A4C5DB02D56ECC4C5BF34007208D5B887185865"
               )
    end
  end

  test "sealed frames go both ways, each opened once, in order" do
    %{phone: phone, server: server} = linked()

    {f1, phone} = Handshake.seal(phone, "one")
    {f2, phone} = Handshake.seal(phone, "two")
    assert {:ok, "one", server} = Handshake.open(server, f1)
    assert {:ok, "two", server} = Handshake.open(server, f2)

    {back, _server} = Handshake.seal(server, "three")
    assert {:ok, "three", _phone} = Handshake.open(phone, back)
  end

  test "a replayed, skipped or tampered frame is refused; a frame never opens in its own direction" do
    %{phone: phone, server: server} = linked()
    {f0, phone} = Handshake.seal(phone, "zero")
    {f1, _phone} = Handshake.seal(phone, "one")

    assert {:error, :out_of_order} = Handshake.open(server, f1)
    {:ok, "zero", server} = Handshake.open(server, f0)
    assert {:error, :replayed} = Handshake.open(server, f0)

    <<head::binary-12, byte, tail::binary>> = f1
    assert {:error, :tampered} = Handshake.open(server, head <> <<Bitwise.bxor(byte, 1)>> <> tail)
    assert {:error, :bad_frame} = Handshake.open(server, <<1, 2, 3>>)

    # sent back to the phone that sealed it, it doesn't open (keys and IV are per direction)
    %{phone: fresh} = linked()
    {own, _} = Handshake.seal(fresh, "echo")
    assert {:error, :tampered} = Handshake.open(fresh, own)
  end

  describe "a tampered transcript fails" do
    test "the hello: another ephemeral key, nonce or signature" do
      %{hello: hello} = linked()
      device = Handshake.keypair()

      for {key, value} <- [
            {"server_eph", Wire.b64(:crypto.strong_rand_bytes(32))},
            {"nonce", Wire.b64(:crypto.strong_rand_bytes(32))},
            {"sig", Wire.b64(:crypto.strong_rand_bytes(64))}
          ] do
        assert Handshake.auth(Map.put(hello, key, value), device_key: device, origin: @origin) ==
                 {:error, :bad_signature}
      end

      assert Handshake.auth(Map.put(hello, "v", 2), device_key: device, origin: @origin) ==
               {:error, :unsupported_version}

      assert Handshake.auth(Map.delete(hello, "nonce"), device_key: device, origin: @origin) ==
               {:error, :bad_frame}
    end

    test "equivalent QR and server origin spellings sign one canonical transcript" do
      server = Handshake.keypair()
      device = Handshake.keypair()
      {hello, pending} = Handshake.hello(server)
      qr = Pairing.qr("HTTPS://STUDY.EXAMPLE.:443/", <<1::128>>, <<2::256>>, elem(server, 0))
      {:ok, %{origin: origin}} = Pairing.parse_qr(qr)

      assert {:ok, auth, _, _} = Handshake.auth(hello, device_key: device, origin: origin)
      assert {:ok, _, _} = Handshake.accept(pending, auth, "HTTPS://STUDY.EXAMPLE.:443/")
      assert {:error, :bad_signature} = Handshake.accept(pending, auth, "https://evil.example")
      assert {:error, :invalid_origin} = Handshake.accept(pending, auth, "http://evil.example")

      assert {:error, :invalid_origin} =
               Handshake.auth(hello, device_key: device, origin: "http://evil.example")
    end

    test "the auth: another origin, ephemeral key, device key, label or signature" do
      %{auth: auth, pending: pending} = linked()

      assert Handshake.accept(pending, auth, "https://evil.example") == {:error, :bad_signature}

      for {key, value} <- [
            {"phone_eph", Wire.b64(elem(:crypto.generate_key(:ecdh, :x25519), 0))},
            {"device_key", Wire.b64(elem(Handshake.keypair(), 0))},
            {"sig", Wire.b64(:crypto.strong_rand_bytes(64))},
            {"platform", "evil"},
            {"app", "9.9"}
          ] do
        assert Handshake.accept(pending, Map.put(auth, key, value), @origin) ==
                 {:error, :bad_signature},
               key
      end

      for bad <- [Map.delete(auth, "platform"), Map.put(auth, "app", 1)] do
        assert Handshake.accept(pending, bad, @origin) == {:error, :bad_frame}
      end
    end

    test "labels are signed as given, and too long ones are refused" do
      {hello, pending} = Handshake.hello(Handshake.keypair())
      device = Handshake.keypair()

      {:ok, auth, _, _} =
        Handshake.auth(hello, device_key: device, origin: @origin, app: "2.1", platform: :android)

      assert {auth["app"], auth["platform"]} == {"2.1", "android"}
      assert {:ok, _, _} = Handshake.accept(pending, auth, @origin)

      long = String.duplicate("x", 256)
      assert Handshake.accept(pending, %{auth | "app" => long}, @origin) == {:error, :bad_frame}

      assert_raise ArgumentError, fn ->
        Handshake.auth(hello, device_key: device, origin: @origin, platform: long)
      end
    end

    test "a device key of small order or not canonical is refused, before any signature" do
      %{auth: auth, pending: pending} = linked()

      # The identity point: OpenSSL takes this "signature" over anything.
      identity = <<1, 0::248>>
      forged = identity <> <<0::256>>
      assert :crypto.verify(:eddsa, :none, "any message", forged, [identity, :ed25519])

      forge = fn key ->
        Handshake.accept(
          pending,
          %{auth | "device_key" => Wire.b64(key), "sig" => Wire.b64(forged)},
          @origin
        )
      end

      assert forge.(identity) == {:error, :bad_frame}

      p = Integer.pow(2, 255) - 19

      order8 =
        for hex <- [
              "26e8958fc2b227b045c3f489f2ef98f0d5dfac05d3c63339b13802886d53fc05",
              "c7176a703d4dd84fba3c0b760d10670f2a2053fa2c39ccc64ec7fd7792ac037a"
            ],
            do: :binary.decode_unsigned(Base.decode16!(hex, case: :lower), :little)

      # the 8 small-order points, the two x = 0 points with the sign bit
      # set, and y not below p
      small = for y <- [0, 1, p - 1 | order8], sign <- [0, 1], do: y + sign * Integer.pow(2, 255)

      for y <- small ++ [p, p + 1, Integer.pow(2, 255) - 1] do
        assert forge.(<<y::little-256>>) == {:error, :bad_frame}, Integer.to_string(y)
      end
    end

    test "an auth signed for another connection (replayed) fails" do
      %{auth: old_auth} = linked()
      %{pending: pending} = linked()
      assert Handshake.accept(pending, old_auth, @origin) == {:error, :bad_signature}
    end
  end

  test "a server key other than the one pinned for the origin aborts" do
    %{hello: hello, server_pub: server_pub} = linked()
    device = Handshake.keypair()

    assert {:ok, _, _, ^server_pub} =
             Handshake.auth(hello, device_key: device, origin: @origin, pinned: server_pub)

    other = elem(Handshake.keypair(), 0)

    assert Handshake.auth(hello, device_key: device, origin: @origin, pinned: other) ==
             {:error, :key_changed}
  end

  test "sessions never show their keys" do
    %{phone: phone} = linked()
    refute inspect(phone) =~ "key"
  end
end
