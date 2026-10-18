defmodule Bezalel.Study.ScrollsTest do
  # The scrolls pack (test/fixtures/packs/scrolls.sqlite, cut by data/'s
  # `mix bezalel.data.fixtures`): its Qumran manuscripts through the ancient
  # tools, its biblical readings through compare_biblical_versions, and both
  # without the pack. Not async: the missing-pack tests repoint :packs_dir.
  use ExUnit.Case, async: false

  alias Bezalel.Study.{Ancient, Citation, DB, Preferences, Sources}
  alias Bezalel.Study.Tools.{CompareBiblicalVersions, LookupAncientSource, SearchAncientSources}

  defp ok(result), do: result |> cited() |> elem(0)

  # A tool's Markdown and its citations.
  defp cited({:ok, {:details, text, %{citations: citations}}}), do: {text, citations}

  @leon_levy "https://www.deadseascrolls.org.il/explore-the-archive/manuscript/"

  defp headings(text), do: for([_, h] <- Regex.scan(~r/^### (.+)$/m, text), do: h)

  defp resolved(citation) do
    assert {:ok, match} = Ancient.resolve(citation, Ancient.corpora())
    {match.work.key, match.fragment || match.sort_range}
  end

  # The fixture packs without the scrolls pack, for the duration of `fun`.
  defp without_scrolls(fun) do
    fixtures = Application.fetch_env!(:bezalel_core, :packs_dir)
    dir = Path.join(System.tmp_dir!(), "bezalel-no-scrolls-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)

    for file <- File.ls!(fixtures),
        file != "scrolls.sqlite",
        do: File.cp!(Path.join(fixtures, file), Path.join(dir, file))

    Application.put_env(:bezalel_core, :packs_dir, dir)

    try do
      fun.()
    after
      Application.put_env(:bezalel_core, :packs_dir, fixtures)
      File.rm_rf!(dir)
    end
  end

  describe "citations" do
    test "a manuscript is cited by siglum, conventional name or collection, by fragment or column" do
      assert resolved("11Q13 2:18") == {"dss_11q13", %{label: "2", lines: {18, 18}}}
      assert resolved("11QMelch ii 18") == {"dss_11q13", %{label: "ii", lines: {18, 18}}}

      assert resolved("4Q174 frg. 1-2 i 10-12") ==
               {"dss_4q174", %{label: "frg. 1–2 i", lines: {10, 12}}}

      assert resolved("Songs of the Sabbath Sacrifice 4Q405 frg. 23 i 2") ==
               {"dss_4q405", %{label: "frg. 23 i", lines: {2, 2}}}

      # A composition's title names its principal copy; a collection prefix a copy.
      assert {"dss_1qm", _} = resolved("War Scroll 5:3")
      assert {"dss_4q491", _} = resolved("War Scroll 4Q491 11 i 3")
      # The ancient pack's works are untouched.
      assert resolved("CD 6:11") == {"damascus_document", {6011, 6011}}
      assert resolved("Damascus Document 6:11") == {"damascus_document", {6011, 6011}}
    end

    test "fragment keys read the ETCBC label and its citation forms alike" do
      assert Ancient.fragment_key("f1_2i") == "f1-2i"
      assert Ancient.fragment_key("frgs. 1–2 col. i") == "f1-2i"
      assert Ancient.fragment_keys("1–2 i") == ["1-2i", "f1-2i"]
      assert Ancient.fragment_keys("ii") == ["ii", "fii", "2"]
      assert Ancient.parse_fragment("5:3–9") == %{label: "5", lines: {3, 9}}
      assert Ancient.parse_fragment("frg. 4") == %{label: "frg. 4", lines: nil}
      # A compound label ending in a fragment number is one label, in either form.
      assert Ancient.parse_fragment("frg. 2 i + 3") == %{label: "frg. 2 i + 3", lines: nil}
      assert Ancient.parse_fragment("frg. 2 i + 3 7") == %{label: "frg. 2 i + 3", lines: {7, 7}}

      assert Ancient.parse_fragment("frg. 2 i + 3 7–11") ==
               %{label: "frg. 2 i + 3", lines: {7, 11}}

      assert Ancient.parse_fragment("f2i+3") == %{label: "f2i+3", lines: nil}
      assert Ancient.parse_fragment("f2i+3 7-11") == %{label: "f2i+3", lines: {7, 11}}
      assert Ancient.parse_fragment("frg. 7 + 5 ii 3") == %{label: "frg. 7 + 5 ii", lines: {3, 3}}
      assert Ancient.parse_fragment("4 9-3") == nil
      assert Ancient.parse_fragment("") == nil
    end

    test "each work names its pack" do
      qumran = Ancient.corpus("qumran")
      assert Ancient.pack(Ancient.work(qumran, "damascus_document")) == :ancient
      assert Ancient.pack(Ancient.work(qumran, "dss_11q13")) == :scrolls
    end
  end

  describe "lookup_ancient_source" do
    test "a column and line: the line window, the copy's date and name" do
      text = ok(LookupAncientSource.run(%{"citation" => "11Q13 2:18"}, %{}))

      assert headings(text) == ["Melchizedek, 11Q13 2:1–25 (11QMelch 2:1–25)"]
      assert text =~ "*Qumran, Melchizedek, 11Q13 2:18: 1 overlapping passage*"
      assert text =~ "copy: 11QMelch, Hasmonean script (c. 150–30 BC)"
      assert text =~ "*Lines 2:16–20 shown (the cited line ±2); cite the column for all of it.*"
      assert text =~ "18 והמבשר הו[אה] מ֯שיח הרו֯[ח]"
      refute text =~ "\n21 "
    end

    test "a scroll passage cites its Leon Levy page as the original: any English is the assistant's" do
      {text, citations} = cited(LookupAncientSource.run(%{"citation" => "11Q13 2:18"}, %{}))
      url = @leon_levy <> "11Q13-1"

      assert text =~
               "\n\nSource: [11Q13 2:1–25](#{url}) (original text: any English you give for it is your own translation"

      assert [
               %Citation{
                 work: "dss",
                 url: ^url,
                 translation: :assistant,
                 original: [%{url: ^url}]
               }
             ] = citations

      # The closing licence list stays.
      assert text =~ "License: CC BY-NC 4.0 (non-commercial;"
    end

    test "a fragment cited without 'frg.', by name, or as a range of fragments" do
      text = ok(LookupAncientSource.run(%{"citation" => "4Q174 1-2 i 10"}, %{}))
      assert headings(text) == ["Florilegium, 4Q174 frg. 1–2 i 1–19 (4QFlor frg. 1–2 i 1–19)"]
      assert text =~ "Lines 8–12 of 4Q174 frg. 1–2 i shown"

      assert ok(LookupAncientSource.run(%{"citation" => "4QFlor frg. 1–2 i 10"}, %{})) =~
               "### Florilegium, 4Q174 frg. 1–2 i 1–19"

      assert {:ok, %{passages: passages}} =
               LookupAncientSource.result(%{"citation" => "4Q174 frg. 11–12"})

      assert Enum.map(passages, & &1.reference) == ["4Q174 frg. 11 1–2", "4Q174 frg. 12 1–5"]
    end

    test "an unknown fragment lists the manuscript's labels; lines past a fragment name its neighbours" do
      assert {:error, message} = LookupAncientSource.run(%{"citation" => "4Q174 frg. 99"}, %{})
      assert message =~ "4Q174 has no fragment or column 'frg. 99'."
      assert message =~ "frg. 1–2 i, frg. 1–3 ii, frg. 4"

      assert ok(LookupAncientSource.run(%{"citation" => "4Q174 frg. 4 40"}, %{})) ==
               "No passage covers 4Q174 frg. 4 40. Nearest passages: preceding " <>
                 "4Q174 frg. 4 1–7, following 4Q174 frg. 5 1–5."
    end
  end

  describe "search_ancient_sources" do
    test "finds the scrolls pack's works by their Hebrew and Aramaic wording" do
      {:ok, war} = SearchAncientSources.result(%{"query" => "בני אור", "corpus" => "qumran"})
      assert "1QM 1:1–20" in Enum.map(war.passages, & &1.reference)

      {:ok, son} = SearchAncientSources.result(%{"query" => "ברה די אל", "corpus" => "qumran"})
      assert [%{reference: "4Q246 frg. 1 ii 1–9", language: "Aramaic"} | _] = son.passages

      assert ok(SearchAncientSources.run(%{"query" => "יתאמר", "corpus" => "all"}, %{})) =~
               "### Aramaic Apocalypse, 4Q246 frg. 1 ii 1–9"
    end

    test "never matches the editors' reconstruction" do
      # 1QM 1:1 has 'סרך' only inside [ ].
      {:ok, result} = SearchAncientSources.result(%{"query" => "סרך", "corpus" => "qumran"})
      refute "1QM 1:1–20" in Enum.map(result[:passages] || [], & &1.reference)
    end
  end

  describe "compare_biblical_versions" do
    test "the DSS witnesses follow the MT and LXX, with siglum, name, locator and what survives" do
      text = ok(CompareBiblicalVersions.run(%{"reference" => "Deuteronomy 32:8"}, %{}))

      assert text =~ "#### DSS Dead Sea Scrolls · 4Q37 (4QDeutj) 12:13–14"
      assert text =~ "/ בני אלוהים […] ׃"

      assert text =~
               "*Preserved: 14 of 53 letters; the rest, in [ ], is the editors' reconstruction"

      assert text =~ "#### DSS Dead Sea Scrolls · 4Q45 (4QpaleoDeutr) frg. 35 3–4"
      assert text =~ "- DSS Dead Sea Scrolls: Hebrew and Aramaic"
      assert text =~ "CC BY-NC 4.0"
    end

    test "each scroll cites its manuscript: Leon Levy's page when the pack names it, else none" do
      {text, citations} =
        cited(CompareBiblicalVersions.run(%{"reference" => "Deuteronomy 32:8"}, %{}))

      deutj = @leon_levy <> "4Q37-1"

      assert text =~
               "**English:** none (any English is the assistant's own).\n" <>
                 "Source: [4Q37 12:13–14](#{deutj}) (original text:"

      assert %Citation{work: "dss", translation: :assistant, licence: "CC BY-NC 4.0"} =
               Enum.find(citations, &(&1.url == deutj))

      # 5/6Hev 1b has no name in the pack, so no Leon Levy page to link.
      {_text, psalm} = cited(CompareBiblicalVersions.run(%{"reference" => "Psalm 22:16"}, %{}))

      assert [%Citation{url: url}, %Citation{label: "5/6hev1b " <> _, url: nil}] =
               Enum.filter(psalm, &(&1.work == "dss"))

      assert url == @leon_levy <> "4Q88-1"
    end

    test "Hebrew numbering is mapped to the canonical verse and said; a wholly reconstructed reading says so" do
      {:ok, psalm} = CompareBiblicalVersions.result(%{"reference" => "Psalm 22:16"})
      dss = Enum.filter(psalm.rows, &(&1.version == "DSS"))
      assert Enum.map(dss, & &1.dss.siglum) == ["4Q88", "5/6hev1b"]
      assert Enum.all?(dss, &(&1.mapping_method == "Hebrew numbering Psa.22.17"))
      assert Enum.any?(dss, &(&1.text =~ "כארו"))
      assert hd(psalm.rows).version == "MT"

      text =
        ok(
          CompareBiblicalVersions.run(
            %{"reference" => "Deuteronomy 1:10", "versions" => ["DSS"]},
            %{}
          )
        )

      assert text =~ "1Q5 (1QDeutb) frg. 1 2"
      assert text =~ "*Nothing legible survives here outside the editors' reconstruction"
      assert text =~ "*Preserved: 18 of 41 letters"

      assert ok(CompareBiblicalVersions.run(%{"reference" => "Malachi 4:1"}, %{})) =~
               "4Q76 (4QXIIa) 4:8–10 (mapping: Hebrew numbering Mal.3.19)"
    end

    test "in Greek numbering the DSS rows follow the LXX verse groups, also when shown alone" do
      for versions <- [["DSS"], ["MT", "LXX", "DSS"]] do
        {:ok, result} =
          CompareBiblicalVersions.result(%{
            "reference" => "Psalm 21:17",
            "numbering" => "lxx",
            "versions" => versions
          })

        dss = Enum.filter(result.rows, &(&1.version == "DSS"))
        assert Enum.map(dss, & &1.dss.siglum) == ["4Q88", "5/6hev1b"], inspect(versions)
        assert Enum.all?(dss, &(&1.canonical_reference == "Psa.22.16"))
      end
    end

    test "verses no scroll preserves are said to be so" do
      assert ok(CompareBiblicalVersions.run(%{"reference" => "Genesis 1:1"}, %{})) =~
               "*No biblical Dead Sea Scroll (ETCBC/dss) preserves any of these verses.*"
    end

    test "the user's DSS source: off drops the witnesses, unless asked for by name" do
      prefs = Preferences.new(excluded_sources: ["manuscripts:dss"])
      {:ok, result} = CompareBiblicalVersions.result(%{"reference" => "Deuteronomy 32:8"}, prefs)
      refute Enum.any?(result.rows, &(&1.version == "DSS"))
      assert result.versions == ["MT", "LXX"]

      assert {:error, message} =
               CompareBiblicalVersions.result(
                 %{"reference" => "Deuteronomy 32:8", "versions" => ["DSS"]},
                 prefs
               )

      assert message == Sources.excluded_message("manuscripts:dss")
      assert %Sources.Source{default_on: true} = Sources.get("manuscripts:dss")
      refute "compare_biblical_versions" in Sources.withheld_tools(prefs)
    end
  end

  # The fixture packs with a scrolls pack that has only pack_meta.
  defp with_damaged_scrolls(fun) do
    fixtures = Application.fetch_env!(:bezalel_core, :packs_dir)
    dir = Path.join(System.tmp_dir!(), "bezalel-damaged-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)

    for file <- File.ls!(fixtures),
        file != "scrolls.sqlite",
        do: File.cp!(Path.join(fixtures, file), Path.join(dir, file))

    {:ok, conn} = Exqlite.Sqlite3.open(Path.join(dir, "scrolls.sqlite"))
    :ok = Exqlite.Sqlite3.execute(conn, "CREATE TABLE pack_meta (key TEXT, value TEXT)")
    :ok = Exqlite.Sqlite3.close(conn)
    Application.put_env(:bezalel_core, :packs_dir, dir)

    try do
      fun.()
    after
      Application.put_env(:bezalel_core, :packs_dir, fixtures)
      File.rm_rf!(dir)
    end
  end

  describe "a scrolls pack that can't be read" do
    test "is searched around, noted in comparisons, and named in lookups" do
      with_damaged_scrolls(fn ->
        text = ok(SearchAncientSources.run(%{"query" => "בני אור", "corpus" => "qumran"}, %{}))
        assert text =~ "The scrolls study pack (Dead Sea Scrolls) isn't downloaded on this device"

        assert {:error, message} = LookupAncientSource.run(%{"citation" => "11Q13 2:18"}, %{})
        assert message =~ "The scrolls study pack on this device can't be read"

        assert ok(CompareBiblicalVersions.run(%{"reference" => "Psalm 22:16"}, %{})) =~
                 "*Dead Sea Scrolls readings need the scrolls study pack"

        assert {:error, message} =
                 CompareBiblicalVersions.run(
                   %{"reference" => "Psalm 22:16", "versions" => ["DSS"]},
                   %{}
                 )

        assert message =~ "can't be read (no dss_biblical_verses, dss_biblical_manuscripts)"
      end)
    end
  end

  # The fixture packs without the ancient pack, for the duration of `fun`.
  defp without_ancient(fun) do
    fixtures = Application.fetch_env!(:bezalel_core, :packs_dir)
    dir = Path.join(System.tmp_dir!(), "bezalel-no-ancient-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)

    for file <- File.ls!(fixtures),
        file != "ancient.sqlite",
        do: File.cp!(Path.join(fixtures, file), Path.join(dir, file))

    Application.put_env(:bezalel_core, :packs_dir, dir)

    try do
      fun.()
    after
      Application.put_env(:bezalel_core, :packs_dir, fixtures)
      File.rm_rf!(dir)
    end
  end

  describe "without the ancient pack" do
    test "a Qumran search reads the scrolls pack and names the missing pack" do
      without_ancient(fn ->
        for corpus <- ["qumran", "all"] do
          text = ok(SearchAncientSources.run(%{"query" => "בני אור", "corpus" => corpus}, %{}))
          assert text =~ "1QM 1:1–20"
          assert text =~ "The ancient study pack (ancient sources) isn't downloaded"
        end

        assert SearchAncientSources.run(%{"query" => "temple", "corpus" => "josephus"}, %{}) ==
                 {:error, DB.missing(:ancient)}

        qumran_off = Preferences.new(excluded_sources: ["ancient:qumran"])

        assert {:error, message} =
                 SearchAncientSources.result(%{"query" => "בני אור"}, qumran_off)

        assert message == DB.missing(:ancient)
      end)
    end

    test "a damaged scrolls pack, or one without Qumran, is named along with the missing pack" do
      without_ancient(fn ->
        dir = Application.fetch_env!(:bezalel_core, :packs_dir)
        scrolls = Path.join(dir, "scrolls.sqlite")
        {:ok, conn} = Exqlite.Sqlite3.open(scrolls)
        :ok = Exqlite.Sqlite3.execute(conn, "DELETE FROM ancient_source_passages")
        :ok = Exqlite.Sqlite3.close(conn)

        assert {:error, message} =
                 SearchAncientSources.run(%{"query" => "בני אור", "corpus" => "qumran"}, %{})

        assert message =~ "The Qumran corpus is not in this device's scrolls pack"

        assert {:error, message} =
                 SearchAncientSources.run(%{"query" => "בני אור", "corpus" => "all"}, %{})

        assert message =~ "This device's scrolls pack has no ancient-source passages"

        File.rm!(scrolls)
        {:ok, conn} = Exqlite.Sqlite3.open(scrolls)
        :ok = Exqlite.Sqlite3.execute(conn, "CREATE TABLE pack_meta (key TEXT, value TEXT)")
        :ok = Exqlite.Sqlite3.close(conn)

        assert {:error, message} =
                 SearchAncientSources.run(%{"query" => "בני אור", "corpus" => "qumran"}, %{})

        assert message =~ DB.missing(:ancient)
        assert message =~ "The scrolls study pack on this device can't be read"
      end)
    end
  end

  describe "without the scrolls pack" do
    test "searches say what wasn't searched, lookups and DSS-only comparisons name the pack" do
      without_scrolls(fn ->
        text = ok(SearchAncientSources.run(%{"query" => "בני אור", "corpus" => "qumran"}, %{}))
        assert text =~ "The scrolls study pack (Dead Sea Scrolls) isn't downloaded on this device"
        refute text =~ "1QM 1:1–20"

        assert LookupAncientSource.run(%{"citation" => "11Q13 2:18"}, %{}) ==
                 {:error, DB.missing(:scrolls)}

        assert {:ok, _} = LookupAncientSource.run(%{"citation" => "CD 6:11"}, %{})

        assert ok(CompareBiblicalVersions.run(%{"reference" => "Psalm 22:16"}, %{})) =~
                 "*Dead Sea Scrolls readings need the scrolls study pack"

        assert CompareBiblicalVersions.run(
                 %{"reference" => "Psalm 22:16", "versions" => ["DSS"]},
                 %{}
               ) ==
                 {:error, DB.missing(:scrolls)}
      end)
    end
  end
end
