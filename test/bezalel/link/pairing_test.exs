defmodule Bezalel.Link.PairingTest do
  use ExUnit.Case, async: true

  alias Bezalel.Link.{Pairing, Wire}

  @pair_id :binary.copy(<<1>>, 16)
  @secret :binary.copy(<<2>>, 32)
  @server_key :binary.copy(<<3>>, 32)

  describe "canonical_origin/1" do
    test "canonicalizes equivalent DNS spellings, IDNA, paths and ports" do
      equivalent = [
        {"https://study.example", "https://study.example"},
        {"HTTPS://STUDY.EXAMPLE", "https://study.example"},
        {"HtTpS://Study.Example./", "https://study.example"},
        {"https://study.example:443", "https://study.example"},
        {"https://study.example:8443/", "https://study.example:8443"},
        {"https://münchen.example", "https://xn--mnchen-3ya.example"},
        {"https://xn--mnchen-3ya.example", "https://xn--mnchen-3ya.example"},
        {"https://ｅｘａｍｐｌｅ.com。", "https://example.com"}
      ]

      for {given, canonical} <- equivalent do
        assert Pairing.canonical_origin(given) == {:ok, canonical}, given
        assert Pairing.canonical_origin(canonical) == {:ok, canonical}, canonical
      end
    end

    test "handles IP literals without ambiguous spellings" do
      assert Pairing.canonical_origin("https://127.0.0.1:443/") ==
               {:ok, "https://127.0.0.1"}

      assert Pairing.canonical_origin("https://[0:0:0:0:0:0:0:1]:8443") ==
               {:ok, "https://[::1]:8443"}

      assert Pairing.canonical_origin("https://[2001:DB8::1]") ==
               {:ok, "https://[2001:db8::1]"}

      assert Pairing.canonical_origin("https://[::ffff:192.0.2.1]") ==
               {:ok, "https://[::ffff:c000:201]"}

      assert Pairing.canonical_origin("https://[2001:db8:0:0:1:0:0:1]") ==
               {:ok, "https://[2001:db8::1:0:0:1]"}

      for ambiguous <- [
            "https://127.00.0.1",
            "https://127.0.0.1.",
            "https://2130706433",
            "https://0x7f000001",
            "https://127.0.0.0x1",
            "https://1.1.1.0x",
            "https://0X",
            "https://127.1",
            "https://256.1.1.1",
            "https://::1",
            "https://[::1",
            "https://::1]",
            "https://[::1]extra",
            "https://[::ffff:192.0.2.1%25eth0]"
          ] do
        assert Pairing.canonical_origin(ambiguous) == {:error, :invalid_origin}, ambiguous
      end
    end

    test "allows plain HTTP only for canonical loopback development origins" do
      assert Pairing.canonical_origin("HTTP://LOCALHOST.:80/") == {:ok, "http://localhost"}
      assert Pairing.canonical_origin("http://127.0.0.1:4000") == {:ok, "http://127.0.0.1:4000"}

      assert Pairing.canonical_origin("http://[0:0:0:0:0:0:0:1]:4000") ==
               {:ok, "http://[::1]:4000"}

      assert Pairing.canonical_origin("http://study.example") == {:error, :invalid_origin}
    end

    test "rejects anything that is not exactly a safe link origin" do
      invalid = [
        nil,
        1,
        "",
        "http://study.example",
        "https:study.example",
        "https:///study.example",
        "https://",
        "https://:443",
        "https://user@study.example",
        "https://user:pass@study.example",
        "https://study.example/path",
        "https://study.example//",
        "https://study.example?next=evil",
        "https://study.example#evil",
        "https://%73tudy.example",
        "https://study%2eexample",
        "https://study.example\\@evil.example",
        "https://.study.example",
        "https://study..example",
        "https://study.example..",
        "https://-study.example",
        "https://study_.example",
        "https://study.example:",
        "https://study.example:+443",
        "https://study.example:0443",
        "https://study.example:0",
        "https://study.example:65536",
        "https://study.example:44x",
        "https://study.example:443:444",
        "https://study.example\n",
        "https://stu\0dy.example",
        <<"https://", 0xFF>>
      ]

      for origin <- invalid do
        assert Pairing.canonical_origin(origin) == {:error, :invalid_origin}, inspect(origin)
      end
    end

    test "rejects every C0, DEL and C1 control character" do
      controls = Enum.to_list(0..31) ++ Enum.to_list(127..159)

      for control <- controls do
        origin = "https://stu" <> <<control::utf8>> <> "dy.example"

        assert Pairing.canonical_origin(origin) == {:error, :invalid_origin},
               Integer.to_string(control)
      end
    end
  end

  describe "QR origin and envelope validation" do
    test "qr/4 emits the canonical origin and parse_qr/1 returns it" do
      qr = Pairing.qr("HTTPS://MÜNCHEN.EXAMPLE.:443/", @pair_id, @secret, @server_key)

      assert {:ok, offer} = Pairing.parse_qr(qr)
      assert offer.origin == "https://xn--mnchen-3ya.example"
      assert offer.pair_id == @pair_id
      assert offer.secret == @secret
      assert Pairing.server_key?(@server_key, offer.server_fingerprint)
    end

    test "qr/4 refuses to emit an invalid origin" do
      assert_raise ArgumentError, "invalid HTTPS origin", fn ->
        Pairing.qr("https://study.example/path", @pair_id, @secret, @server_key)
      end
    end

    test "parse_qr/1 rejects duplicate, missing and extra query fields" do
      fields = qr_fields("https://study.example")
      query = URI.encode_query(fields, :rfc3986)

      duplicates =
        Enum.map(fields, fn field ->
          "bezalel://link?" <> query <> "&" <> URI.encode_query([field], :rfc3986)
        end)

      malicious =
        duplicates ++
          [
            "bezalel://link?o=https%3A%2F%2Fevil.example&" <> query,
            "bezalel://link?" <> query <> "&x=ignored",
            "bezalel://link?" <> query <> "&",
            "bezalel://link?&" <> query,
            "bezalel://link?" <> query <> "&&x=ignored",
            "bezalel://link?" <> URI.encode_query(tl(fields), :rfc3986),
            "bezalel://link?%6f=https%3A%2F%2Fevil.example&" <> query
          ]

      for qr <- malicious do
        assert Pairing.parse_qr(qr) == {:error, :not_a_link}, qr
      end
    end

    test "parse_qr/1 rejects ambiguous outer link URI components" do
      query = URI.encode_query(qr_fields("https://study.example"), :rfc3986)

      for qr <- [
            "bezalel://user@link?" <> query,
            "bezalel://link:443?" <> query,
            "bezalel://link/?" <> query,
            "bezalel://link/path?" <> query,
            "bezalel://link?" <> query <> "#fragment",
            "bezalel://LINK?" <> query,
            "bezalel:////link?" <> query,
            " bezalel://link?" <> query,
            "bezalel://link?" <> query <> "\n"
          ] do
        assert Pairing.parse_qr(qr) == {:error, :not_a_link}, qr
      end
    end

    test "parse_qr/1 validates and canonicalizes a received origin" do
      qr = "bezalel://link?" <> URI.encode_query(qr_fields("HTTPS://STUDY.EXAMPLE.:443/"))
      assert {:ok, %{origin: "https://study.example"}} = Pairing.parse_qr(qr)

      for origin <- [
            "http://study.example",
            "https://user@study.example",
            "https://study.example/path",
            "https://%73tudy.example",
            "https://127.00.0.1"
          ] do
        qr = "bezalel://link?" <> URI.encode_query(qr_fields(origin), :rfc3986)
        assert Pairing.parse_qr(qr) == {:error, :not_a_link}, origin
      end
    end
  end

  defp qr_fields(origin) do
    [
      {"o", origin},
      {"p", Wire.b64(@pair_id)},
      {"s", Wire.b64(@secret)},
      {"k", Pairing.server_fingerprint(@server_key)}
    ]
  end
end
