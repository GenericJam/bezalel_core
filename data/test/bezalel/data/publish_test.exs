defmodule Bezalel.Data.PublishTest do
  use ExUnit.Case, async: true

  alias Bezalel.Data.Publish

  @sha "a" |> String.duplicate(64)
  @raw_sha "b" |> String.duplicate(64)

  @pin %{
    "url" => "https://bezalel.genericjam.com/packs/v1/core.sqlite.zst",
    "sha256" => @sha,
    "size" => 10,
    "raw_sha256" => @raw_sha,
    "raw_size" => 20
  }

  @base %{
    "bezalel_mob_commit" => "0c1b349",
    "studybible_mcp" => %{
      "repo" => "https://github.com/djayatillake/studybible-mcp",
      "commit" => "38cef28"
    },
    "packs" => %{"core" => @pin}
  }

  @published_core Map.merge(@pin, %{
                    "name" => "core",
                    "description" => "Hebrew and Greek texts",
                    "required" => true,
                    "licence" => "CC BY 4.0",
                    "compression" => "zstd",
                    "tables" => ["verses", "bsb_verses"]
                  })

  @published %{"schema" => 1, "data_version" => 1, "packs" => [@published_core]}

  describe "base_entries/2" do
    test "keeps base.json's files and the published description, licence, required and tables" do
      assert {:ok, [entry]} = Publish.base_entries(@base, @published)
      assert entry == @published_core
    end

    test "keeps the published order and leaves out packs that aren't base packs" do
      notes = %{@published_core | "name" => "notes", "url" => "https://x/notes"}

      base =
        put_in(
          @base,
          ["packs", "notes"],
          Map.take(notes, ~w(url sha256 size raw_sha256 raw_size))
        )

      translations = %{@published_core | "name" => "translations"}
      published = %{@published | "packs" => [notes, @published_core, translations]}

      assert {:ok, [%{"name" => "notes"}, %{"name" => "core"}]} =
               Publish.base_entries(base, published)
    end

    test "refuses a published base that isn't base.json's" do
      changed = put_in(@published, ["packs"], [%{@published_core | "raw_sha256" => @sha}])

      assert {:error, ["core: published raw_sha256 differ from base.json"]} =
               Publish.base_entries(@base, changed)

      assert {:error, ["core: not in the published manifest"]} =
               Publish.base_entries(@base, %{@published | "packs" => []})
    end
  end

  test "the translations entry points at the new version and is optional" do
    entry =
      Publish.entry("translations", 2, %{size: 3, sha256: @sha}, %{size: 9, sha256: @raw_sha}, [
        "translations",
        "translation_verses"
      ])

    assert %{
             "name" => "translations",
             "required" => false,
             "description" =>
               "English Bible translations: the NET Bible, the JPS 1917 (Old Testament), and " <>
                 "the Literal and Simplified Texts (ULT, UST, adapted)",
             "url" => "https://bezalel.genericjam.com/packs/v2/translations.sqlite.zst",
             "compression" => "zstd",
             "size" => 3,
             "sha256" => @sha,
             "raw_size" => 9,
             "raw_sha256" => @raw_sha,
             "tables" => ["translations", "translation_verses"]
           } = entry

    assert entry["licence"] =~ "non-commercial"
    assert entry["licence"] =~ "CC BY-SA 4.0"
    assert entry["licence"] =~ "original work by unfoldingWord is available from"
  end

  test "the scrolls entry is optional and carries the CC BY-NC licence; packs built here are both" do
    entry =
      Publish.entry("scrolls", 2, %{size: 3, sha256: @sha}, %{size: 9, sha256: @raw_sha}, ["t"])

    assert %{
             "name" => "scrolls",
             "required" => false,
             "url" => "https://bezalel.genericjam.com/packs/v2/scrolls.sqlite.zst"
           } = entry

    assert entry["licence"] =~ "CC BY-NC 4.0"
    assert Publish.built_here() == ["translations", "scrolls"]

    assert_raise KeyError, fn ->
      Publish.entry("core", 2, %{size: 1, sha256: @sha}, %{size: 1, sha256: @sha}, [])
    end
  end

  test "a scrolls pack is refused unless built from the pins, the base core and this code" do
    meta = %{
      "dss_sha256" => "d",
      "dss_source" => "s",
      "core_sha256" => "c",
      "build_sha256" => "b"
    }

    expected = %{dss_sha256: "d", dss_source: "s", core_sha256: "c", build_sha256: "b"}

    assert Publish.check_scrolls(meta, expected) == :ok

    assert {:error, "wasn't built from pins.json's ETCBC/dss"} =
             Publish.check_scrolls(meta, %{expected | dss_sha256: "x"})

    assert {:error, "wasn't numbered with base.json's core pack"} =
             Publish.check_scrolls(meta, %{expected | core_sha256: "x"})

    assert {:error, "was built by other code than this checkout's"} =
             Publish.check_scrolls(Map.delete(meta, "build_sha256"), expected)
  end

  test "a translations pack is refused unless built from every pinned source and the base core" do
    meta = %{
      "net_sha256" => "n",
      "jps_sha256" => "j",
      "ult_sha256" => "l",
      "ust_sha256" => "s",
      "core_sha256" => "c"
    }

    assert Publish.check_translations(meta, meta) == :ok

    assert {:error, "wasn't built from pins.json's jps, ust"} =
             Publish.check_translations(meta, %{meta | "jps_sha256" => "x", "ust_sha256" => "x"})

    # A pack from before the JPS, ULT and UST (the NET alone) is refused.
    assert {:error, "wasn't built from pins.json's jps, ult, ust"} =
             Publish.check_translations(Map.take(meta, ~w(net_sha256 core_sha256)), meta)

    assert {:error, "wasn't numbered with base.json's core pack"} =
             Publish.check_translations(meta, %{meta | "core_sha256" => "x"})
  end

  describe "manifest/4" do
    setup do
      {:ok, [base_entry]} = Publish.base_entries(@base, @published)

      new =
        Publish.entry("translations", 2, %{size: 3, sha256: @sha}, %{size: 9, sha256: @raw_sha}, [
          "t"
        ])

      opts = [version: 2, built: "2026-10-17T00:00:00Z", core_commit: "1bc6dd8"]
      %{manifest: Publish.manifest(@base, [base_entry], [new], opts), base_entry: base_entry}
    end

    test "base packs unchanged, the new pack added, provenance named", %{
      manifest: m,
      base_entry: b
    } do
      assert %{
               "schema" => 1,
               "data_version" => 2,
               "built" => "2026-10-17T00:00:00Z",
               "bezalel_commit" => "0c1b349",
               "bezalel_core" => %{
                 "repo" => "https://github.com/GenericJam/bezalel_core",
                 "commit" => "1bc6dd8"
               },
               "studybible_mcp" => %{"commit" => "38cef28"},
               "sources" =>
                 "https://github.com/GenericJam/bezalel_mob/blob/master/data/SOURCES.md",
               "packs" => [^b, %{"name" => "translations"}]
             } = m
    end

    test "a new pack replaces a base entry of the same name", %{base_entry: b} do
      rebuilt = %{b | "url" => "https://bezalel.genericjam.com/packs/v2/core.sqlite.zst"}
      opts = [version: 2, built: "x", core_commit: "c"]
      assert %{"packs" => [^rebuilt]} = Publish.manifest(@base, [b], [rebuilt], opts)
    end

    test "encodes with the published key order and every field the app's parser requires",
         %{manifest: m} do
      json = Publish.encode(m)
      assert String.ends_with?(json, "}\n")
      assert json =~ ~r/\A\{\n  "schema": 1,\n  "data_version": 2,\n  "built"/

      assert json =~
               ~r/"repo": "https:\/\/github.com\/djayatillake\/studybible-mcp",\n    "commit"/

      assert json =~ "©1996"

      decoded = Jason.decode!(json)
      assert decoded == m

      for pack <- decoded["packs"] do
        assert %{"compression" => "zstd", "url" => "https://" <> _} = pack
        assert is_integer(pack["size"]) and pack["size"] > 0
        assert is_integer(pack["raw_size"]) and pack["raw_size"] > 0
        assert byte_size(pack["sha256"]) == 64 and byte_size(pack["raw_sha256"]) == 64
      end

      # The first pack's keys (none of them is a top-level key) in the published order.
      keys =
        ~w(name description required licence url compression size sha256 raw_size raw_sha256 tables)

      positions = Enum.map(keys, fn key -> json |> :binary.match(~s("#{key}":)) |> elem(0) end)
      assert positions == Enum.sort(positions)
    end
  end
end
