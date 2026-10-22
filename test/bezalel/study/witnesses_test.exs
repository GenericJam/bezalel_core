defmodule Bezalel.Study.WitnessesTest do
  # The witnesses pack (test/fixtures/packs/witnesses.sqlite, cut by data/'s
  # `mix bezalel.data.fixtures --pack witnesses`) through
  # compare_biblical_versions, get_textual_variant and lookup_verse, and the
  # same tools without it. Not async: the missing-pack tests repoint
  # :packs_dir.
  use ExUnit.Case, async: false

  alias Bezalel.Study.{Citation, DB, Preferences, Sources}
  alias Bezalel.Study.Tools.{CompareBiblicalVersions, GetTextualVariant, LookupVerse}

  defp ok(result), do: result |> cited() |> elem(0)
  defp cited({:ok, {:details, text, %{citations: citations}}}), do: {text, citations}

  defp without_witnesses(fun), do: without(["witnesses.sqlite"], fun)

  # The fixture packs without `files`, for the duration of `fun`.
  defp without(files, fun) do
    fixtures = Application.fetch_env!(:bezalel_core, :packs_dir)

    dir =
      Path.join(System.tmp_dir!(), "bezalel-no-witnesses-#{System.unique_integer([:positive])}")

    File.mkdir_p!(dir)

    for file <- File.ls!(fixtures),
        file not in files,
        do: File.cp!(Path.join(fixtures, file), Path.join(dir, file))

    Application.put_env(:bezalel_core, :packs_dir, dir)

    try do
      fun.()
    after
      Application.put_env(:bezalel_core, :packs_dir, fixtures)
      File.rm_rf!(dir)
    end
  end

  describe "get_textual_variant by which packs are on the device" do
    test "witnesses without notes: the HOTTP and apparatus data, with a note" do
      without(["notes.sqlite"], fn ->
        text = ok(GetTextualVariant.run(%{"reference" => "Genesis 4:8"}, %{}))
        assert text =~ "The notes study pack (studybible-mcp's curated textual-variant cases"
        assert text =~ "### HOTTP entry 00015"

        assert ok(GetTextualVariant.run(%{"reference" => "John 1:18"}, %{})) =~
                 "- **SBLGNT:** μονογενὴς θεὸς — WH, Treg, NA28"

        # Nothing in the witnesses pack for the verse: the notes pack's error.
        assert GetTextualVariant.run(%{"reference" => "Genesis 1:2"}, %{}) ==
                 {:error, DB.missing(:notes)}
      end)
    end

    test "neither pack: the notes pack's error" do
      without(["notes.sqlite", "witnesses.sqlite"], fn ->
        assert GetTextualVariant.run(%{"reference" => "Genesis 4:8"}, %{}) ==
                 {:error, DB.missing(:notes)}
      end)
    end

    test "notes without witnesses: the notes pack's cases only, no note" do
      without_witnesses(fn ->
        text = ok(GetTextualVariant.run(%{"reference" => "Deuteronomy 32:8"}, %{}))
        assert text =~ "## Variant at Deu.32.8"
        refute text =~ "HOTTP"
        refute text =~ "notes study pack"
      end)
    end

    test "both packs: no missing-pack note" do
      refute ok(GetTextualVariant.run(%{"reference" => "Genesis 4:8"}, %{})) =~ "notes study pack"
    end
  end

  describe "compare_biblical_versions: the Samaritan Pentateuch" do
    test "a Torah verse shows MT, LXX and SP, the SP cited with its dataset and licence" do
      {text, citations} = cited(CompareBiblicalVersions.run(%{"reference" => "Genesis 1:1"}, %{}))

      assert text =~ "#### MT "
      assert text =~ "#### LXX "
      assert text =~ "#### SP Samaritan Pentateuch · Gen.1.1"
      [_, sp_part] = String.split(text, "#### SP Samaritan Pentateuch · Gen.1.1\n")
      assert [hebrew | _] = String.split(sp_part, "\n")
      assert hebrew =~ "**Hebrew:** "
      assert hebrew =~ "ברא אלהים את"

      assert text =~ "- SP Samaritan Pentateuch: consonantal Hebrew only"
      assert text =~ "CC BY-NC 4.0"

      sp = Enum.find(citations, &(&1.work == "sp"))
      assert sp.url =~ "https://github.com/DT-UCPH/sp/tree/6da31aa"
      assert sp.licence == "CC BY-NC 4.0"
      assert sp.translation == :assistant
    end

    test "rows keep the dataset's Hebrew number and its verse-division notes" do
      {:ok, result} =
        CompareBiblicalVersions.result(
          %{"reference" => "Exodus 8:1", "versions" => ["SP"]},
          Preferences.new([])
        )

      assert [%{edition_reference: "Exo.7.26", mapping_method: "Hebrew numbering Exo.7.26"}] =
               result.rows

      text =
        ok(
          CompareBiblicalVersions.run(%{"reference" => "Exodus 26:35", "versions" => ["SP"]}, %{})
        )

      assert text =~ "*Verse division: The Samaritan Pentateuch has the incense altar"

      {:ok, num} =
        CompareBiblicalVersions.result(
          %{"reference" => "Numbers 26:1", "versions" => ["SP"]},
          Preferences.new([])
        )

      assert Enum.map(num.rows, & &1.edition_reference) == ["Num.25.19", "Num.26.1"]
    end

    test "outside the Torah SP is left out, and alone it is an error; switched off it is dropped" do
      {:ok, result} =
        CompareBiblicalVersions.result(%{"reference" => "Psalm 22:1"}, Preferences.new([]))

      refute "SP" in result.versions

      assert {:error, message} =
               CompareBiblicalVersions.result(
                 %{"reference" => "Psalm 22:1", "versions" => ["SP"]},
                 Preferences.new([])
               )

      assert message =~ "only Genesis–Deuteronomy"

      prefs = Preferences.new(excluded_sources: ["manuscripts:sp"])
      {:ok, off} = CompareBiblicalVersions.result(%{"reference" => "Genesis 1:1"}, prefs)
      refute Enum.any?(off.rows, &(&1.version == "SP"))

      assert {:error, excluded} =
               CompareBiblicalVersions.result(
                 %{"reference" => "Genesis 1:1", "versions" => ["SP"]},
                 prefs
               )

      assert excluded == Sources.excluded_message("manuscripts:sp")
    end
  end

  describe "compare_biblical_versions: the New Testament" do
    test "the core Greek (TAGNT) beside the SBLGNT, each labelled and cited" do
      {text, citations} = cited(CompareBiblicalVersions.run(%{"reference" => "John 3:16"}, %{}))

      assert text =~ "#### TAGNT STEPBible TAGNT (Translators Amalgamated Greek NT) · Jhn.3.16"
      assert text =~ "#### SBLGNT SBL Greek New Testament · Jhn.3.16"
      assert text =~ "an amalgamated text: every word found in the major editions"
      refute text =~ "Verse mapping:"

      sblgnt = Enum.find(citations, &(&1.work == "sblgnt"))

      assert sblgnt.url =~
               ~r{Faithlife/SBLGNT/blob/c4d241a[0-9a-f]*/data/sblgnt/text/John\.txt#L\d+$}
    end

    test "a verse the SBLGNT doesn't print beside the core Greek is said so" do
      {:ok, result} =
        CompareBiblicalVersions.result(%{"reference" => "John 3:13-17"}, Preferences.new([]))

      versions = result.rows |> Enum.map(& &1.version) |> Enum.uniq()
      assert versions == ["TAGNT", "SBLGNT"]
      refute CompareBiblicalVersions.render(result) =~ "doesn't print Jhn.3.13"
    end
  end

  describe "get_textual_variant" do
    test "a verse with no notes-pack case returns its HOTTP entry, rating and factors explained" do
      {text, citations} = cited(GetTextualVariant.run(%{"reference" => "Genesis 4:8"}, %{}))

      assert text =~ "## UBS Hebrew Old Testament Text Project (HOTTP) at Gen.4.8"
      assert text =~ "### HOTTP entry 00015"

      assert text =~
               "**The HOTTP committee's judgment** (its conclusion, not manuscript evidence):"

      assert text =~ "- Rating **B** for reading 1: This form of the text probably represents"
      assert text =~ "- Factors cited for reading 2: 8, 4, 7."

      assert text =~
               "- **Factor 4, Simplification of the text (easier reading)** (factors of modification)"

      assert Enum.map(citations, & &1.label) == [
               "HOTTP entry 00015 (Genesis 4:8)",
               "HOTTP: the committee's ratings",
               "HOTTP: factors involved in textual decisions"
             ]
    end

    test "an NT verse returns the SBLGNT apparatus with its sigla" do
      {text, [citation]} = cited(GetTextualVariant.run(%{"reference" => "John 1:18"}, %{}))

      assert text =~ "- **SBLGNT:** μονογενὴς θεὸς — WH, Treg, NA28"
      assert text =~ "- **Variant:** ὁ μονογενὴς υἱός — RP"
      assert text =~ "RP: Robinson and Pierpont"
      assert citation.url =~ "data/sblgntapp/xml/John.xml#L"
    end

    test "a unit spanning verses, WH's double brackets, and a note kept raw" do
      luke = ok(GetTextualVariant.run(%{"reference" => "Luke 22:43"}, %{}))
      assert luke =~ "### Variation unit 1 (verses 43–44)"
      assert luke =~ "(the same words, in Westcott and Hort's double brackets) — ⟦WH⟧"

      john = ok(GetTextualVariant.run(%{"reference" => "John 7:52"}, %{}))
      assert john =~ "The note as the apparatus gives it (not split into readings)"
    end

    test "the notes pack's case comes first, then HOTTP" do
      text = ok(GetTextualVariant.run(%{"reference" => "Deuteronomy 32:8"}, %{}))
      [notes, hottp] = String.split(text, "## UBS Hebrew Old Testament Text Project")
      assert notes =~ "## Variant at Deu.32.8"
      assert hottp =~ "HOTTP entry 00684"
    end
  end

  test "lookup_verse hints at the HOTTP entries of a passage" do
    {:ok, result} = LookupVerse.result(%{"reference" => "Genesis 1:1-7"}, Preferences.new([]))
    assert result.hints.witnesses.hottp == ["Gen.1.1", "Gen.1.6", "Gen.1.7"]

    assert LookupVerse.render(result) =~
             "*Text-critical notes in the UBS Hebrew Old Testament Text Project (HOTTP) in this " <>
               "passage: Genesis 1:1, Genesis 1:6, Genesis 1:7."
  end

  describe "without the witnesses pack" do
    test "compare notes the missing SP and SBLGNT, errs only when asked for alone" do
      without_witnesses(fn ->
        text = ok(CompareBiblicalVersions.run(%{"reference" => "Genesis 1:1"}, %{}))
        assert text =~ "Samaritan Pentateuch readings need the witnesses study pack"
        refute text =~ "#### SP"

        nt = ok(CompareBiblicalVersions.run(%{"reference" => "John 3:16"}, %{}))
        assert nt =~ "The SBL Greek New Testament needs the witnesses study pack"
        assert nt =~ "#### TAGNT"

        for versions <- [["SP"], ["SBLGNT"]] do
          reference = if versions == ["SP"], do: "Genesis 1:1", else: "John 3:16"

          assert {:error, message} =
                   CompareBiblicalVersions.run(
                     %{"reference" => reference, "versions" => versions},
                     %{}
                   )

          assert message =~ "The witnesses study pack"
        end
      end)
    end

    test "get_textual_variant and lookup_verse behave as before" do
      without_witnesses(fn ->
        assert ok(GetTextualVariant.run(%{"reference" => "Genesis 4:8"}, %{})) ==
                 "No textual-variant case or NT quotation alignment is catalogued for Genesis 4:8."

        {:ok, result} = LookupVerse.result(%{"reference" => "Genesis 1:1-7"}, Preferences.new([]))
        assert result.hints.witnesses == %{hottp: [], apparatus: []}
        refute LookupVerse.render(result) =~ "Text-critical notes"
      end)
    end
  end

  test "every citation the tools give has a URL" do
    {_, citations} = cited(GetTextualVariant.run(%{"reference" => "1 Samuel 1:24"}, %{}))
    assert citations != [] and Enum.all?(citations, &is_binary(&1.url))
    assert Citation.source_line(citations) =~ "HOTTP entry 00985"
  end
end
