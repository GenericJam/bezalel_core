defmodule Bezalel.Study.TranslationsTest do
  # The English the tools quote: the NET from the translations pack, the
  # BSB from the core pack, and the BSB with a note when the user chose the
  # NET but the translations pack isn't there. Changes the packs directory,
  # so not async. The pack here is a stand-in written by the test (its
  # "NET" texts are markers, not the NET's wording).
  use ExUnit.Case, async: false

  alias Bezalel.Study.{Citation, DB, Preferences, Translations, Verses}

  alias Bezalel.Study.Tools.{
    FindSimilarPassages,
    GraphEnrichedSearch,
    LookupVerse,
    SearchByStrongs,
    WordStudy
  }

  alias Exqlite.Sqlite3

  @net Preferences.new(translation: "net")
  @bsb Preferences.new(translation: "bsb")

  setup do
    fixtures = Application.fetch_env!(:bezalel_core, :packs_dir)

    dir =
      Path.join(System.tmp_dir!(), "bezalel-translations-#{System.unique_integer([:positive])}")

    File.mkdir_p!(dir)

    for pack <- ~w(core notes graph),
        do: File.ln_s!(Path.join(fixtures, "#{pack}.sqlite"), Path.join(dir, "#{pack}.sqlite"))

    Application.put_env(:bezalel_core, :packs_dir, dir)

    on_exit(fn ->
      Application.put_env(:bezalel_core, :packs_dir, fixtures)
      File.rm_rf!(dir)
    end)

    %{dir: dir}
  end

  defp write_pack(dir, verses) do
    {:ok, conn} = Sqlite3.open(Path.join(dir, "translations.sqlite"))

    :ok =
      Sqlite3.execute(conn, """
      CREATE TABLE pack_meta (key TEXT PRIMARY KEY, value TEXT NOT NULL) WITHOUT ROWID;
      INSERT INTO pack_meta VALUES ('pack', 'translations');
      CREATE TABLE translation_verses (
        translation TEXT NOT NULL, reference TEXT NOT NULL, book TEXT NOT NULL,
        chapter INTEGER NOT NULL, verse INTEGER NOT NULL, text TEXT NOT NULL,
        PRIMARY KEY (translation, reference));
      """)

    for {reference, text} <- verses do
      [book, chapter, verse] = String.split(reference, ".")

      :ok =
        Sqlite3.execute(
          conn,
          "INSERT INTO translation_verses VALUES ('net', '#{reference}', '#{book}', " <>
            "#{chapter}, #{verse}, '#{text}')"
        )
    end

    Sqlite3.close(conn)
  end

  test "the NET from the translations pack, labelled and linked, with the translation as data", %{
    dir: dir
  } do
    write_pack(dir, [
      {"Exo.31.2", "NET marker for Exodus 31:2"},
      {"Exo.31.3", "NET marker for Exodus 31:3"},
      {"Psa.22.0", "NET marker for the superscription"},
      {"Psa.22.1", "NET marker for Psalm 22:1"}
    ])

    assert {:ok, result} = LookupVerse.result(%{"reference" => "Ex 31:2-3"}, @net)
    assert result.translation == %{key: "net", abbreviation: "NET", url: "http://netbible.org"}
    assert result.translation_note == nil

    assert Enum.map(result.verses, & &1.english) == [
             "NET marker for Exodus 31:2",
             "NET marker for Exodus 31:3"
           ]

    assert Enum.all?(result.verses, & &1.translated)
    # The words stay STEPBible's.
    assert Enum.any?(hd(result.verses).words, &(&1.strongs == "H1212G"))

    text = LookupVerse.render(result)
    assert text =~ ~r/\A# Ex 31:2-3 \(\[NET\]\(http:\/\/netbible\.org\)\)\n/
    refute text =~ "BSB"

    # A split-numbered verse and a superscription find their NET text by
    # their English numbers.
    assert {:ok, psalm} = LookupVerse.result(%{"reference" => "Psalm 22:0-1"}, @net)

    assert Enum.map(psalm.verses, & &1.english) ==
             ["NET marker for the superscription", "NET marker for Psalm 22:1"]

    # A verse the pack lacks falls back to the marked gloss, not the BSB.
    assert {:ok, %{verses: [gap]}} = LookupVerse.result(%{"reference" => "Exodus 31:4"}, @net)
    refute gap.translated
    assert gap.english =~ "[gloss]"

    # Its source is its original on STEP alone: no NET page for a gloss.
    assert {:ok, gap_result} = LookupVerse.result(%{"reference" => "Exodus 31:4"}, @net)
    assert [%Citation{work: "step", url: step_url}] = LookupVerse.citations(gap_result)
    assert step_url =~ "reference=Exo.31.4"
    refute LookupVerse.render(gap_result) =~ "netbible.org/bible"
  end

  test "the other tools that quote English use the chosen translation", %{dir: dir} do
    write_pack(dir, [{"Exo.31.3", "NET marker for Exodus 31:3"}])

    graph = %{"reference" => "Exodus 31:3"}
    assert {:ok, net} = GraphEnrichedSearch.result(graph, @net)
    assert net.verse.english == "NET marker for Exodus 31:3"
    assert GraphEnrichedSearch.render(net) =~ "## Exodus 31:3 ([NET](http://netbible.org))"

    assert {:ok, bsb} = GraphEnrichedSearch.result(graph, @bsb)
    assert bsb.verse.english =~ "And I have filled him with the Spirit of God"
    assert GraphEnrichedSearch.render(bsb) =~ "## Exodus 31:3 (BSB)"

    assert {:ok, strongs} = SearchByStrongs.result(%{"strongs" => "H7307", "limit" => 20}, @net)

    assert %{english: "NET marker for Exodus 31:3"} =
             Enum.find(strongs.verses, &(&1.reference == "Exo.31.3"))

    assert strongs.translation.key == "net"

    assert {:ok, study} = WordStudy.result(%{"strongs" => "H7307"}, @net)

    assert %{english: "NET marker for Exodus 31:3"} =
             Enum.find(study.examples, &(&1.reference == "Exo.31.3"))

    assert WordStudy.render(study) =~ "## Example Passages ([NET](http://netbible.org))"

    # An example in the NET cites its NET page; one shown in the gloss, STEP.
    assert WordStudy.render(study) =~
             "**Exo.31.3**: NET marker for Exodus 31:3\n" <>
               "Source: [Exodus 31:3](https://netbible.org/bible/Exodus+31:3)\n"

    assert %Citation{work: "step"} =
             Enum.find(WordStudy.citations(study), &(&1.locator == "Gen.1.2"))

    assert {:ok, similar} = FindSimilarPassages.result(%{"reference" => "Exodus 31:3"}, @net)
    assert similar.source.english == "NET marker for Exodus 31:3"
  end

  test "the NET chosen without the translations pack: the BSB, with a one-line note" do
    assert {:ok, result} = LookupVerse.result(%{"reference" => "Exodus 31:3"}, @net)
    assert result.translation.key == "bsb"
    assert result.translation_note =~ "The NET Bible isn't on this device"
    assert hd(result.verses).english =~ "And I have filled him with the Spirit of God"

    text = LookupVerse.render(result)

    assert text =~
             ~r/\A\*The NET Bible isn't on this device \(the translations pack isn't downloaded\), so this English is the BSB\.\*\n\n## Exo\.31\.3 \(BSB\)\n/
  end

  test "the BSB chosen needs no translations pack and says nothing about it" do
    assert {:ok, result} = LookupVerse.result(%{"reference" => "Exodus 31:3"}, @bsb)
    assert result.translation_note == nil
    assert LookupVerse.render(result) =~ ~r/\A## Exo\.31\.3 \(BSB\)\n/
  end

  test "with_translation opens the translations pack once and hands the call its connection",
       %{dir: dir} do
    write_pack(dir, [{"Exo.31.3", "NET marker for Exodus 31:3"}])

    assert Translations.with_translation("net", fn translation, note ->
             assert note == nil
             assert %{key: "net", conn: _} = translation
             :called
           end) == :called

    assert Translations.with_translation("bsb", fn translation, nil ->
             refute Map.has_key?(translation, :conn)
             translation.key
           end) == "bsb"
  end

  test "the verse queries read the NET through the call's connection, not by opening the pack",
       %{dir: dir} do
    # The packs directory has no translations pack; the connection is to one
    # elsewhere, so only a lookup through it finds the text.
    elsewhere = Path.join(dir, "elsewhere")
    File.mkdir_p!(elsewhere)
    write_pack(elsewhere, [{"Exo.31.3", "Read through the call connection"}])
    {:ok, tconn} = Sqlite3.open(Path.join(elsewhere, "translations.sqlite"), mode: :readonly)
    net = Map.put(Translations.get("net"), :conn, tconn)

    try do
      assert {:ok, [row]} = DB.with_pack(:core, &Verses.passage(&1, "Exo", {31, 3}, {31, 3}, net))
      assert row["text_translation"] == "Read through the call connection"

      assert {:ok, [row]} =
               DB.with_pack(
                 :core,
                 &Verses.passage(&1, "Exo", {31, 3}, {31, 3}, Translations.get("net"))
               )

      assert row["text_translation"] == nil
    after
      Sqlite3.close(tconn)
    end
  end

  test "a translation the pack doesn't have (a pack from before it): the BSB, with a note",
       %{dir: dir} do
    write_pack(dir, [{"Gen.1.1", "NET marker for Genesis 1:1"}])

    assert {:ok, result} =
             LookupVerse.result(
               %{"reference" => "Genesis 1:1"},
               Preferences.new(translation: "ult")
             )

    assert result.translation.key == "bsb"

    assert result.translation_note ==
             "The Literal Text (ULT, adapted) isn't in the translations pack on this device " <>
               "(the pack needs updating), so this English is the BSB."
  end
end

defmodule Bezalel.Study.TranslationsFixtureTest do
  # The fixture translations pack (the NET of every verse the core fixture's
  # BSB has, cut by the phone app's data scripts): the default translation.
  use ExUnit.Case, async: true

  alias Bezalel.Study.Preferences
  alias Bezalel.Study.Tools.LookupVerse

  test "by default lookup_verse quotes the NET, linked as its terms ask" do
    assert {:ok, result} = LookupVerse.result(%{"reference" => "Exodus 31:3"}, %Preferences{})
    assert result.translation.key == "net"
    assert result.translation_note == nil

    assert LookupVerse.render(result) =~
             ~r/\A## Exo\.31\.3 \(\[NET\]\(http:\/\/netbible\.org\)\)\n\nand I have filled him with the Spirit of God in skill/

    assert {:ok, psalm} = LookupVerse.result(%{"reference" => "Psalm 22:0-1"}, %Preferences{})

    assert Enum.map(psalm.verses, & &1.english) == [
             "For the music director, according to the tune “Morning Doe”; a psalm of David.",
             "My God, my God, why have you abandoned me? I groan in prayer, but help seems far away."
           ]
  end
end

defmodule Bezalel.Study.TranslationsCoverageTest do
  # The JPS 1917, ULT and UST from the fixture translations pack (cut from
  # the real one), and the BSB standing in, with one note, for a book the
  # chosen translation doesn't have: the JPS's New Testament, a book not in
  # the ULT's release (Isaiah, Ezekiel).
  use ExUnit.Case, async: true

  alias Bezalel.Agent.Card
  alias Bezalel.Study.{Citation, Citations, Preferences}
  alias Bezalel.Study.Tools.{GetCrossReferences, LookupVerse, SearchByStrongs, WordStudy}

  @jps Preferences.new(translation: "jps1917")
  @ult Preferences.new(translation: "ult")
  @ust Preferences.new(translation: "ust")

  test "the JPS 1917 on Genesis 1:1, labelled (JPS) and linked to its eBible verse" do
    assert {:ok, result} = LookupVerse.result(%{"reference" => "Genesis 1:1"}, @jps)
    assert result.translation.key == "jps1917"
    assert result.translation_note == nil
    assert [%{english: "IN THE beginning God created the heaven and the earth."}] = result.verses

    assert LookupVerse.render(result) =~ ~r/\A## Gen\.1\.1 \(JPS\)\n\nIN THE beginning/

    assert %Citation{work: "jps", url: "https://ebible.org/engjps/GEN01.htm#V1"} =
             Enum.find(LookupVerse.citations(result), &(&1.work == "jps"))

    card = Card.from_tool("lookup_verse", result)
    assert card["version"] == "JPS"
    assert [%{"url" => "https://ebible.org/engjps/GEN01.htm#V1"}] = card["verses"]
  end

  test "the JPS 1917 on John 3:16: the BSB, labelled (BSB), with one note saying why" do
    assert {:ok, result} = LookupVerse.result(%{"reference" => "John 3:16"}, @jps)
    assert result.translation.key == "bsb"

    assert result.translation_note ==
             "The JPS 1917 covers the Old Testament only; New Testament verses are quoted " <>
               "from the BSB."

    assert [%{english: "For God so loved the world" <> _, translated: true, fallback: false}] =
             result.verses

    assert LookupVerse.render(result) =~
             ~r/\A\*The JPS 1917 covers the Old Testament only; New Testament verses are quoted from the BSB\.\*\n\n## Jhn\.3\.16 \(BSB\)\n/

    assert Enum.any?(LookupVerse.citations(result), &(&1.work == "bsb"))
    refute Enum.any?(LookupVerse.citations(result), &(&1.work == "jps"))
    assert Card.from_tool("lookup_verse", result)["version"] == "BSB"
  end

  test "the ULT on a book its release lacks (Isaiah): the BSB with the note" do
    assert {:ok, result} = LookupVerse.result(%{"reference" => "Isaiah 3:18"}, @ult)
    assert result.translation.key == "bsb"

    assert result.translation_note ==
             "The Literal Text (ULT, adapted) doesn't include Isaiah, so it is quoted from the BSB."

    assert [%{english: "In that day the Lord will take away" <> _}] = result.verses
    assert LookupVerse.render(result) =~ "## Isa.3.18 (BSB)\n"
  end

  test "the ULT and UST where they have the book, superscription included, linked to Door43's reader" do
    assert {:ok, psalm} = LookupVerse.result(%{"reference" => "Psalm 22:0-1"}, @ult)
    assert psalm.translation.key == "ult"
    assert psalm.translation_note == nil

    assert Enum.map(psalm.verses, & &1.english) == [
             "For the chief musician; on “The Doe of the Dawn.” A psalm of David.",
             "My God, my God, why have you forsaken me? {Why are you} far from the salvation " <>
               "of me, {far from} the words of my groaning?"
           ]

    assert LookupVerse.render(psalm) =~ ~r/\A# Psalm 22:1 \(ULT\)\n/

    urls = Enum.map(LookupVerse.citations(psalm), & &1.url)
    assert "https://preview.door43.org/u/unfoldingWord/en_ult/v91/?book=psa#psa-22-1" in urls

    assert {:ok, ust} = LookupVerse.result(%{"reference" => "Genesis 1:1"}, @ust)
    assert ust.translation.key == "ust"

    assert LookupVerse.render(ust) =~
             ~r/\A## Gen\.1\.1 \(UST\)\n\n\{This is how everything\} began/
  end

  test "word_study and search_by_strongs mix: the BSB, labelled per verse, only where the book is missing" do
    assert {:ok, study} = WordStudy.result(%{"strongs" => "H7307"}, @ult)
    assert study.translation.key == "ult"

    assert study.translation_note ==
             "The Literal Text (ULT, adapted) doesn't include Ezekiel, so it is quoted from the BSB."

    assert %{fallback: true} = Enum.find(study.examples, &(&1.book == "Ezk"))
    assert %{fallback: false} = Enum.find(study.examples, &(&1.reference == "Gen.1.2"))

    text = WordStudy.render(study)
    assert text =~ "## Example Passages (ULT)\n"

    assert text =~
             ~r/\*\*Ezk\.27\.26\*\* \(BSB\): .*\nSource: \[Ezekiel 27:26\]\(https:\/\/biblehub\.com\/ezekiel\/27-26\.htm\)/

    assert text =~
             ~r/\*\*Gen\.1\.2\*\*: .*\nSource: \[Genesis 1:2\]\(https:\/\/preview\.door43\.org/

    assert {:ok, strongs} = SearchByStrongs.result(%{"strongs" => "H0776", "limit" => 50}, @ult)

    assert strongs.translation_note ==
             "The Literal Text (ULT, adapted) doesn't include Isaiah or Ezekiel, so those books " <>
               "are quoted from the BSB."

    assert SearchByStrongs.render(strongs) =~ ~r/\*\*Isa\.\d+\.\d+\*\* \(BSB\): /

    # A Greek word's examples are all New Testament: with the JPS chosen,
    # every one is the BSB's, and the result says so once.
    assert {:ok, greek} = WordStudy.result(%{"strongs" => "G0026"}, @jps)
    assert greek.translation.key == "bsb"
    assert greek.translation_note =~ "The JPS 1917 covers the Old Testament only"
    refute WordStudy.render(greek) =~ "(BSB):"
  end

  test "cross references link a verse the translation lacks to the BSB's page" do
    assert {:ok, result} = GetCrossReferences.result(%{"reference" => "John 3:16"}, @jps)
    assert "Jhn" in result.bsb_books

    for citation <- tl(GetCrossReferences.citations(result)),
        do: assert(citation.work == "bsb")
  end

  test "the citations of the new translations" do
    assert Citations.jps("Psa.22.0").url == "https://ebible.org/engjps/PSA022.htm#V1"
    assert Citations.jps({"Mal", 4, 1}).url == "https://ebible.org/engjps/MAL04.htm#V1"

    assert Citations.ult({"1Sa", 3, 10}).url ==
             "https://preview.door43.org/u/unfoldingWord/en_ult/v91/?book=1sa#1sa-3-10"

    assert Citations.scripture("Tit.1.1", "ust").url ==
             "https://preview.door43.org/u/unfoldingWord/en_ust/v91/?book=tit#tit-1-1"

    assert Citations.work_title("ult") == "Literal Text (ULT, adapted)"
  end
end
