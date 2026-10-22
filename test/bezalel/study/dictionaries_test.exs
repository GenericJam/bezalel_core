defmodule Bezalel.Study.DictionariesTest do
  # The dictionaries pack (test/fixtures/packs/dictionaries.sqlite, cut by
  # data/'s `mix bezalel.data.fixtures`): the UBS dictionaries' meanings in
  # word_study, and word_study without the pack. Not async: the
  # missing-pack tests repoint :packs_dir.
  use ExUnit.Case, async: false

  alias Bezalel.Study.{Citation, Dictionaries, Preferences}
  alias Bezalel.Study.Tools.WordStudy

  @prefs Preferences.new(limit: 4, translation: "bsb")
  @commit "a15a96cfaa4ca18a6c0339016645ba1e534db3c8"

  defp study(strongs) do
    assert {:ok, result} = WordStudy.result(%{"strongs" => strongs}, @prefs)
    result
  end

  # The fixture packs with `dictionaries.sqlite` replaced by `fun.(dir)`'s
  # (nothing, for a missing pack), for the duration of `test`.
  defp with_dictionaries(write, test) do
    fixtures = Application.fetch_env!(:bezalel_core, :packs_dir)
    dir = Path.join(System.tmp_dir!(), "bezalel-dict-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)

    for file <- File.ls!(fixtures),
        file != "dictionaries.sqlite",
        do: File.cp!(Path.join(fixtures, file), Path.join(dir, file))

    write.(Path.join(dir, "dictionaries.sqlite"))
    Application.put_env(:bezalel_core, :packs_dir, dir)

    try do
      test.()
    after
      Application.put_env(:bezalel_core, :packs_dir, fixtures)
      File.rm_rf!(dir)
    end
  end

  describe "word_study with the dictionaries pack" do
    test "אֱלֹהִים: BDB as before, then SDBH's meanings with their domains and a Source line" do
      text = WordStudy.render(study("H430"))

      assert text =~ "### Full BDB Definition"
      assert text =~ "\n## UBS Dictionary of Biblical Hebrew: אֱלֹהִים (H0430) — *noun m*\n"

      assert text =~
               "3. **Names of Deities (source domain: Deities)** — plural with singular meaning: " <>
                 "= the highest God, creator of heaven and earth\n   Glosses: God · 1066 references\n"

      assert text =~
               "Source: [UBS Dictionary of Biblical Hebrew, אֱלֹהִים (H0430)](https://github.com/ubsicap/ubs-open-license/blob/#{@commit}/dictionaries/hebrew/JSON/UBSHebrewDic-v0.9.4-en.JSON)"
    end

    test "רוּחַ: its references in the packs' English numbering (Hebrew Job 41:8 is Job 41:16)" do
      text = WordStudy.render(study("H7307"))
      assert text =~ "### Full BDB Definition"
      assert text =~ "1. **Deities** — = a manifestation of God"

      assert text =~
               "ranging in intensity from a light breeze (Job.41.16) to a heavy blast (Job.1.19)"
    end

    test "ἀγάπη: LSJ as before, then Louw–Nida's meanings with number, domain and subdomain" do
      result = study("G26")
      text = WordStudy.render(result)

      assert text =~ "### Full LSJ Definition"

      assert text =~
               "1. LN 25.43 · **Attitudes and Emotions › Love, Affection, Compassion** — to have " <>
                 "love for someone or something, based on sincere appreciation and high regard\n" <>
                 "   Glosses: to love; to regard with affection; loving concern; love · 115 references\n" <>
                 "   Note: Though some persons"

      assert text =~ "2. LN 23.28 · **Physiological Processes and States › Eat, Drink**"

      assert %Citation{
               work: "ubs_greek",
               label: label,
               url:
                 "https://github.com/ubsicap/ubs-open-license/blob/" <>
                   @commit <> "/dictionaries/greek/JSON/UBSGreekNTDic-v1.1-en.JSON"
             } = Enum.find(WordStudy.citations(result), &(&1.work == "ubs_greek"))

      # UBS writes ά as the Greek Extended oxia (U+1F71), canonically the tonos ά.
      assert String.normalize(label, :nfc) ==
               String.normalize("UBS Dictionary of the Greek New Testament, ἀγάπη (G0026)", :nfc)
    end

    test "an Aramaic number: the UBS entry giving A2452 is the core lexicon's H2452" do
      text = WordStudy.render(study("H2452"))
      assert text =~ "## UBS Dictionary of Biblical Hebrew: חָכְמָה (A2452)"
    end
  end

  describe "word_study without the dictionaries pack" do
    test "missing: the entry, its Source line and the examples as they were, no UBS section" do
      with_dictionaries(fn _path -> :ok end, fn ->
        result = study("H7307")
        assert result.dictionary == %{entries: [], more: 0}
        text = WordStudy.render(result)
        refute text =~ "UBS"

        assert [
                 %Citation{work: "step"},
                 %Citation{work: "bdb"},
                 %Citation{work: "strongs"},
                 %Citation{work: "bsb"} | _
               ] = citations = WordStudy.citations(result)

        assert text =~
                 "\n" <>
                   Citation.source_line(Enum.take(citations, 3)) <>
                   "\n\n## Example Passages (BSB)"

        refute WordStudy.render(study("G26")) =~ "UBS"
      end)
    end

    test "damaged (no tables): silently left out too" do
      write = fn path ->
        {:ok, conn} = Exqlite.Sqlite3.open(path)
        :ok = Exqlite.Sqlite3.execute(conn, "CREATE TABLE pack_meta (key TEXT, value TEXT)")
        :ok = Exqlite.Sqlite3.close(conn)
      end

      with_dictionaries(write, fn ->
        refute WordStudy.render(study("H7307")) =~ "UBS"
      end)
    end
  end

  describe "section/1" do
    test "an entry's meanings are capped, saying how many are left out; extra entries are counted" do
      meaning = fn n ->
        %{
          position: n,
          part_of_speech: "noun",
          louw_nida: nil,
          definition: "meaning #{n}",
          glosses: ["g#{n}"],
          comments: nil,
          reference_count: 1,
          domains: [%{kind: "domain", code: "001", name: "Objects", source: nil}]
        }
      end

      entry = %{
        dictionary: "ubs_hebrew",
        title: "UBS Dictionary of Biblical Hebrew",
        lemma: "x",
        codes: "H0001",
        meanings: Enum.map(1..12, meaning)
      }

      text = Dictionaries.section(%{entries: [entry], more: 2})
      assert text =~ "10. **Objects** — meaning 10\n"
      refute text =~ "meaning 11"
      assert text =~ "*[10 of 12 meanings shown; the rest are in the UBS entry]*"
      assert text =~ "*[2 more UBS dictionary entries for this number not shown]*"

      long = %{
        entry
        | meanings: Enum.map(1..3, &%{meaning.(&1) | definition: String.duplicate("a", 2000)})
      }

      text = Dictionaries.section(%{entries: [long], more: 0})
      assert text =~ "*[1 of 3 meanings shown; the rest are in the UBS entry]*"
    end
  end
end
