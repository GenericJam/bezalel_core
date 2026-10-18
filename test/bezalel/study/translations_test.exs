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
