defmodule Bezalel.Study.FathersTest do
  # The fathers pack (test/fixtures/packs/fathers.sqlite, cut by data/'s
  # `mix bezalel.data.fixtures`): the Apostolic Fathers through the ancient
  # tools, their machine-translated English labelled as such, and the
  # searches and lookups without the pack. Not async: the missing-pack tests
  # repoint :packs_dir.
  use ExUnit.Case, async: false

  alias Bezalel.Study.{Ancient, Citation, Citations, DB}
  alias Bezalel.Study.Tools.{LookupAncientSource, SearchAncientSources}

  @lake "https://github.com/jtauber/apostolic-fathers/blob/a07f9207902d2a7a88aa3e7c8fb3671d7ef6f0ff/texts/"
  @cafe "https://github.com/jcuenod/CAFE/blob/06b19aecf94f2342c6061502a2b481b03693eaa3/"

  defp cited({:ok, {:details, text, %{citations: citations}}}), do: {text, citations}
  defp ok(result), do: result |> cited() |> elem(0)

  defp references({:ok, %{passages: passages}}), do: Enum.map(passages, & &1.reference)

  defp resolved(citation) do
    assert {:ok, match} = Ancient.resolve(citation, Ancient.corpora())
    {match.work.key, match.sort_range}
  end

  # The fixture packs without `pack` (:missing), with `pack` reduced to
  # pack_meta (:damaged), or with its tables but no passages (:empty), for
  # the duration of `fun`.
  defp with_packs(change, fun) do
    fixtures = Application.fetch_env!(:bezalel_core, :packs_dir)
    dir = Path.join(System.tmp_dir!(), "bezalel-fathers-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    for file <- File.ls!(fixtures), do: File.cp!(Path.join(fixtures, file), Path.join(dir, file))

    for {pack, how} <- change do
      file = Path.join(dir, "#{pack}.sqlite")
      if how != :empty, do: File.rm!(file)

      sql =
        case how do
          :missing -> nil
          :damaged -> "CREATE TABLE pack_meta (key TEXT, value TEXT)"
          :empty -> "DELETE FROM ancient_source_passages"
        end

      if sql do
        {:ok, conn} = Exqlite.Sqlite3.open(file)
        :ok = Exqlite.Sqlite3.execute(conn, sql)
        :ok = Exqlite.Sqlite3.close(conn)
      end
    end

    Application.put_env(:bezalel_core, :packs_dir, dir)

    try do
      fun.()
    after
      Application.put_env(:bezalel_core, :packs_dir, fixtures)
      File.rm_rf!(dir)
    end
  end

  describe "citations" do
    test "each work is cited as Lake numbers it, the Shepherd by part" do
      assert resolved("Didache 9.1") == {"didache", {9001, 9001}}
      assert resolved("Did. 9") == {"didache", {9000, 9999}}
      assert resolved("1 Clement 5.4") == {"1_clement", {5004, 5004}}

      assert resolved("Ignatius, To the Ephesians 20.2") ==
               {"ignatius_ephesians", {20_002, 20_002}}

      assert resolved("Ign. Eph. 20.2") == {"ignatius_ephesians", {20_002, 20_002}}

      assert resolved("Polycarp, To the Philippians 10.1") ==
               {"polycarp_philippians", {10_001, 10_001}}

      assert resolved("Hermas Vision 1.1.1") == {"hermas_visions", {1_001_001, 1_001_001}}

      assert resolved("Shepherd of Hermas, Mandate 4.1.1") ==
               {"hermas_mandates", {4_001_001, 4_001_001}}

      assert resolved("Sim. 9.30.3") == {"hermas_similitudes", {9_030_003, 9_030_003}}

      assert resolved("Martyrdom of Polycarp, Moscow epilogue 1") ==
               {"martyrdom_of_polycarp_moscow_epilogue", {1, 1}}

      assert resolved("Martyrdom of Polycarp 9.3") == {"martyrdom_of_polycarp", {9003, 9003}}
      # The Shepherd has five Visions; a bare 'Romans' is no Ignatian letter.
      assert {:bad_locator, _} = Ancient.resolve("Vision 6.1.1", Ancient.corpora())
      assert Ancient.resolve("Romans 5.1", Ancient.corpora()) == :unknown_work
    end

    test "every work is in the fathers pack, dated, tiered and not Scripture" do
      corpus = Ancient.corpus("apostolic_fathers")

      for work <- corpus.works do
        assert Ancient.pack(work) == :fathers
        assert work.tag.status =~ "Not Scripture"
        assert work.tag.tier in ["B", "A/B"]
      end

      assert Ancient.work(corpus, "1_clement").tag.tier == "A/B"
      assert Ancient.work(corpus, "1_clement").tag.status =~ "Codex Alexandrinus"
      assert Ancient.work(corpus, "barnabas").tag.status =~ "Codex Sinaiticus"
    end

    test "a passage cites CAFE's English line as a machine translation, Lake's Greek line as the original" do
      citation =
        Citations.ancient("didache", "Didache 9.1", source_url: @lake <> "011-didache.txt#L51")

      assert %Citation{
               work: "apostolic_fathers",
               translation: :machine,
               url: @cafe <> "011-didache.en.txt#L51",
               original: [%{url: @lake <> "011-didache.txt#L51"}]
             } = citation

      assert Citation.markdown(citation) =~
               "(machine translation: AI-generated English, not a published human translation"

      assert citation |> Citation.to_map() |> Citation.from_map() == citation

      # Without the English the Greek is cited, and any English is the assistant's.
      assert %Citation{translation: :assistant, url: @lake <> "011-didache.txt#L51"} =
               Citations.ancient("didache", "Didache 9.1",
                 source_url: @lake <> "011-didache.txt#L51",
                 english: false
               )
    end

    test "the CAFE commit cited is the one data/pins.json builds from" do
      pin = "data/pins.json" |> File.read!() |> JSON.decode!() |> get_in(["fathers", "english"])
      assert @cafe == "#{pin["repo"]}/blob/#{pin["commit"]}/"
    end
  end

  describe "search_ancient_sources" do
    test "finds a passage by its English or Greek wording, labelled as a machine translation" do
      {text, citations} =
        cited(SearchAncientSources.run(%{"query" => "Lord's day", "corpus" => "all"}, %{}))

      assert text =~ "### Anonymous, Didache 14.1"
      assert text =~ "On the Lord's Day, when you gather together"
      assert text =~ "**Greek:** Κατὰ κυριακὴν δὲ κυρίου"
      assert text =~ "CAFE machine-translated English"

      assert text =~
               "English: CAFE, Contemporary Apostolic Fathers Edition (James Cuénod, 2024): a machine translation"

      assert text =~
               "Source: [Didache 14.1 (CAFE, machine translation)](#{@cafe}011-didache.en.txt#L87) " <>
                 "(machine translation: AI-generated English"

      assert [%Citation{translation: :machine, url: @cafe <> "011-didache.en.txt#L87"}] =
               citations

      # The closing sources name the file, not every line.
      assert text =~ ~r/License: CC BY-SA 4\.0\. #{Regex.escape(@lake)}011-didache\.txt$/m

      assert references(
               SearchAncientSources.result(%{
                 "query" => "ὁδοὶ δύο",
                 "corpus" => "apostolic_fathers"
               })
             ) ==
               ["Didache 1.1", "Barnabas 18.1"]

      assert references(
               SearchAncientSources.result(%{
                 "query" => "two ways",
                 "corpus" => "apostolic_fathers"
               })
             ) ==
               ["Barnabas 18.1"]

      assert references(
               SearchAncientSources.result(%{
                 "query" => "medicine of immortality",
                 "corpus" => "all"
               })
             ) ==
               ["Ignatius, To the Ephesians 20.2"]
    end

    test "a Latin passage is labelled Latin" do
      assert {:ok, %{passages: [passage | _]}} =
               SearchAncientSources.result(%{
                 "query" => "exemplar sequimini",
                 "corpus" => "apostolic_fathers"
               })

      assert passage.reference == "Polycarp, To the Philippians 10.1"
      assert passage.language == "Latin"
    end
  end

  describe "lookup_ancient_source" do
    test "reads a passage by its citation" do
      text = ok(LookupAncientSource.run(%{"citation" => "Ignatius, To the Ephesians 20.2"}, %{}))
      assert text =~ "## Ignatius, To the Ephesians 20.2"
      assert text =~ "which is the medicine of immortality"
      assert text =~ "φάρμακον ἀθανασίας"

      assert references(LookupAncientSource.result(%{"citation" => "Didache 9.1"})) == [
               "Didache 9.1"
             ]

      assert references(LookupAncientSource.result(%{"citation" => "1 Clement 5.4"})) == [
               "1 Clement 5.4"
             ]

      assert references(LookupAncientSource.result(%{"citation" => "Hermas Vision 1.1.1"})) ==
               ["Hermas, Vision 1.1.1"]

      assert references(LookupAncientSource.result(%{"citation" => "Mandate 4.1.1"})) ==
               ["Hermas, Mandate 4.1.1"]
    end
  end

  describe "without the fathers pack" do
    test "other corpora are searched with a note; the fathers alone, and a citation, name the pack" do
      with_packs([fathers: :missing], fn ->
        text = ok(SearchAncientSources.run(%{"query" => "temple", "corpus" => "all"}, %{}))
        assert text =~ "War 6.316"

        assert text =~
                 "The fathers study pack (Apostolic Fathers) isn't downloaded on this device"

        refute ok(SearchAncientSources.run(%{"query" => "temple", "corpus" => "josephus"}, %{})) =~
                 "fathers study pack"

        assert SearchAncientSources.run(
                 %{"query" => "Lord's day", "corpus" => "apostolic_fathers"},
                 %{}
               ) ==
                 {:error, DB.missing(:fathers)}

        assert LookupAncientSource.run(%{"citation" => "Didache 9.1"}, %{}) ==
                 {:error, DB.missing(:fathers)}
      end)
    end

    test "a damaged pack is searched around, and named when it is all that was asked for" do
      with_packs([fathers: :damaged], fn ->
        assert ok(SearchAncientSources.run(%{"query" => "temple", "corpus" => "all"}, %{})) =~
                 "The fathers study pack (Apostolic Fathers) isn't downloaded on this device (or can't be read)"

        assert {:error, message} =
                 SearchAncientSources.run(
                   %{"query" => "Lord's day", "corpus" => "apostolic_fathers"},
                   %{}
                 )

        assert message =~ "The fathers study pack on this device can't be read"
      end)
    end
  end

  describe "without the ancient pack" do
    test "a search of every corpus reads the fathers and scrolls packs and names the missing pack" do
      with_packs([ancient: :missing], fn ->
        text = ok(SearchAncientSources.run(%{"query" => "Lord's day", "corpus" => "all"}, %{}))
        assert text =~ "### Anonymous, Didache 14.1"

        assert text =~
                 "The ancient study pack (ancient sources) isn't downloaded on this device, so only " <>
                   "the Dead Sea Scrolls and the Apostolic Fathers were searched"

        assert references(
                 SearchAncientSources.result(%{
                   "query" => "Lord's day",
                   "corpus" => "apostolic_fathers"
                 })
               ) ==
                 ["Didache 14.1"]
      end)
    end

    test "an empty pack beside it is an error naming the missing ancient pack and the empty one" do
      for empty <- [:scrolls, :fathers] do
        with_packs([ancient: :missing] ++ [{empty, :empty}], fn ->
          assert {:error, message} =
                   SearchAncientSources.run(%{"query" => "Lord's day", "corpus" => "all"}, %{})

          assert String.starts_with?(message, DB.missing(:ancient))
          assert message =~ "This device's #{empty} pack has no ancient-source passages"
        end)
      end
    end
  end

  describe "with the ancient pack and an empty pack beside it" do
    test "the empty pack is searched around and noted" do
      with_packs([scrolls: :empty], fn ->
        text = ok(SearchAncientSources.run(%{"query" => "temple", "corpus" => "all"}, %{}))
        assert text =~ "War 6.316"

        assert text =~
                 "The scrolls study pack (Dead Sea Scrolls) isn't downloaded on this device (or " <>
                   "can't be read), so only CD, 1QS, 1QSa and 1QpHab of the Qumran works were searched"

        refute text =~ "fathers study pack"
      end)

      with_packs([fathers: :empty], fn ->
        assert ok(SearchAncientSources.run(%{"query" => "temple", "corpus" => "all"}, %{})) =~
                 "The fathers study pack (Apostolic Fathers) isn't downloaded on this device"
      end)
    end
  end

  describe "the Moscow epilogue" do
    test "is the copyists' note, not the church of Smyrna's" do
      corpus = Ancient.corpus("apostolic_fathers")

      assert Ancient.work(corpus, "martyrdom_of_polycarp_moscow_epilogue").author ==
               "Anonymous (copyists' note)"

      assert Ancient.work(corpus, "martyrdom_of_polycarp").author == "Church of Smyrna"

      assert ok(
               LookupAncientSource.run(
                 %{"citation" => "Martyrdom of Polycarp, Moscow epilogue 1"},
                 %{}
               )
             ) =~ "### Anonymous (copyists' note), Martyrdom of Polycarp, Moscow epilogue 1"
    end
  end
end
