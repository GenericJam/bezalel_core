defmodule Bezalel.Study.Tools.LookupVerseTest do
  # Ported from studybible-mcp's tests/test_lookup_verse.py (and the
  # lookup_verse cases of test_textual_variants.py and
  # test_variant_witnesses.py), against the fixture packs
  # (test/fixtures/packs: Genesis 1-2, Exodus 31, Psalm 22, John 3 and Jude
  # from the real core pack, the verses make_fixtures.py's EXTRA_VERSES
  # names, and all the notes pack's textual-variant cases and quotations).
  use ExUnit.Case, async: true

  alias Bezalel.Study.Preferences
  alias Bezalel.Study.Tools.LookupVerse

  # These cases read the BSB (the core pack) with the genre guidance on, as
  # studybible-mcp's output had it; the NET's are in translations_test.exs.
  @bsb Preferences.new(translation: "bsb", excluded_sources: ["editorial:verdicts"])

  defp lookup(reference, args \\ %{}) do
    {:ok, result} = LookupVerse.result(Map.put(args, "reference", reference), @bsb)
    LookupVerse.render(result)
  end

  defp error(reference) do
    {:error, message} = LookupVerse.run(%{"reference" => reference}, %{})
    message
  end

  # The verse headings ('## Exo.31.2', a single verse's with " (BSB)"), in order.
  defp headings(text) do
    for [_, ref] <- Regex.scan(~r/^## (\S+\.\d+\.\d+\S*)(?: \(BSB\))?$/m, text), do: ref
  end

  defp occurrences(text, part), do: text |> String.split(part) |> Enum.count() |> Kernel.-(1)

  test "a verse range returns every verse in order under the range's heading" do
    text = lookup("Ex 31:2-3")
    assert headings(text) == ["Exo.31.2", "Exo.31.3"]
    assert text =~ ~r/\A# Ex 31:2-3 \(BSB\)\n/
  end

  test "an en dash separates a range" do
    assert headings(lookup("Exodus 31:2\u20133")) == ["Exo.31.2", "Exo.31.3"]
  end

  test "a whole chapter returns the chapter" do
    text = lookup("Exodus 31")
    assert headings(text) == for(v <- 1..18, do: "Exo.31.#{v}")
    assert text =~ ~r/\A# Exodus 31 \(BSB\)\n/
  end

  test "a cross-chapter range" do
    assert headings(lookup("Genesis 1:30-2:2")) == ["Gen.1.30", "Gen.1.31", "Gen.2.1", "Gen.2.2"]
  end

  test "an OT verse stored with split English(Hebrew) numbering is found by its English number" do
    assert headings(lookup("Psalm 22:1")) == ["Psa.22.1(22.2)"]
    assert headings(lookup("Psalm 22:1-2")) == ["Psa.22.1(22.2)", "Psa.22.2(22.3)"]
  end

  test "a single verse is the plain verse, BSB-labelled, with its word list and cross-reference hint" do
    text = lookup("Exodus 31:3")
    assert text =~ ~r/\A## Exo.31.3 \(BSB\)\n\nAnd I have filled him with the Spirit of God/
    assert text =~ "### Word Analysis"
    assert text =~ "(H7307G): [the] spirit of\n"
    assert text =~ "(H2451): with/ skill\n"
    assert text =~ "(H4390): and/ I have filled\n"
    assert text =~ "## Genre: Old Testament Narratives"
    assert text =~ "`get_cross_references` (reference='Exodus 31:3')"
  end

  test "the passage hints come once, pointing at the passage's first verse" do
    text = lookup("Psalm 22:0-2")
    assert occurrences(text, "## Genre:") == 1
    assert occurrences(text, "get_cross_references") == 1
    assert text =~ "(e.g. reference='Psalm 22:1')"
  end

  test "the original-text and morphology flags apply to every verse" do
    plain = lookup("John 3:16-18", %{"include_original" => false})
    refute plain =~ "### Original Text"
    refute plain =~ "### Word Analysis"

    parsed = lookup("John 3:16-18", %{"include_morphology" => true})
    assert occurrences(parsed, "### Original Text") == 3
    assert occurrences(parsed, "### Word Analysis") == 3
    assert parsed =~ "(G0025): loved [V-AAI-3S]"
  end

  test "a passage omits the word list unless morphology is requested" do
    passage = lookup("John 3:16-18")
    assert occurrences(passage, "### Original Text") == 3
    refute passage =~ "### Word Analysis"
  end

  test "more than 50 verses are cut, with the continuation named" do
    text = lookup("Genesis 1-2")
    found = headings(text)
    assert Enum.count(found) == 50
    assert List.last(found) == "Gen.2.19"
    assert text =~ ~r/\A# Genesis 1:1-2:19 \(BSB\)\n/

    assert text =~
             "*Showing the first 50 of 56 verses. Continue with reference='Genesis 2:20-25'.*"
  end

  test "a range past the chapter's end is clamped with a note" do
    text = lookup("Exodus 31:17-40")
    assert headings(text) == ["Exo.31.17", "Exo.31.18"]
    assert text =~ "*Exodus 31 ends at verse 18; showing through 31:18.*"
  end

  for {reference, message} <- [
        # The fixture has a few Exodus chapters, so not 1–40.
        {"Exodus 41", "Exodus has no chapter 41 (chapters "},
        {"Exodus 31:30", "Exodus 31 has no verse 30 (verses 1–18)."},
        {"Exodus 31:5-3", "Invalid range 'Exodus 31:5-3': the end comes before the start."},
        {"Nonsense 1:1", "Unknown book 'Nonsense'"},
        {"what is love", "Supported forms: a verse ('John 3:16'), a verse range"},
        {"", "Please provide a verse reference"}
      ] do
    test "#{inspect(reference)} is an error the model can act on" do
      assert error(unquote(reference)) =~ unquote(message)
    end
  end

  test "single-chapter books are cited by verse alone" do
    assert headings(lookup("Jude 3")) == ["Jud.1.3"]
    assert headings(lookup("Jude 3-5")) == ["Jud.1.3", "Jud.1.4", "Jud.1.5"]
    assert Enum.count(headings(lookup("Jude"))) == 25
    # A lone "1" is the chapter, as chapter-level tools expect.
    assert Enum.count(headings(lookup("Jude 1"))) == 25
  end

  test "a Psalm superscription is labelled and shown without counting as a verse" do
    text = lookup("Psalm 22:0-2", %{"include_original" => false})
    assert text =~ "## Psa.22 superscription (Hebrew Psa.22.1)"
    refute text =~ "Psa.22.0(22.1)"
    assert headings(text) == ["Psa.22.1(22.2)", "Psa.22.2(22.3)"]
    assert text =~ ~r/\A# Psalm 22:1-2 \(BSB\)/

    chapter = lookup("Psalm 22", %{"include_original" => false})
    assert chapter =~ ~r/\A# Psalm 22 \(BSB\)\n/
    assert Enum.count(headings(chapter)) == 31
  end

  test "result/1 gives the passage card its words with Strong's numbers" do
    {:ok, result} = LookupVerse.result(%{"reference" => "Ex 31:2-3"}, @bsb)
    assert result.book == "Exo"
    assert result.label == "Ex 31:2-3"

    assert result.translation == %{
             key: "bsb",
             abbreviation: "BSB",
             url: "https://bereanbible.com"
           }

    assert result.translation_note == nil
    assert [bezalel_verse, spirit_verse] = result.verses
    assert bezalel_verse.reference == "Exo.31.2"
    assert bezalel_verse.translated
    assert bezalel_verse.english =~ "Bezalel son of Uri"
    assert %{gloss: "Bezalel"} = Enum.find(bezalel_verse.words, &(&1.strongs == "H1212G"))
    assert ~w(H4390 H7307G H2451) -- Enum.map(spirit_verse.words, & &1.strongs) == []
  end

  describe "hints" do
    test "a Torah verse or passage points to its weave partners; other books don't" do
      verse = lookup("Exodus 31:2")
      assert occurrences(verse, "Torah Weave") == 1

      assert verse =~
               "*Torah Weave structural partners available for this verse via " <>
                 "`get_torah_weave` (reference='Exodus 31:2')"

      assert lookup("Genesis 1:1-3") =~
               "*Torah Weave structural partners are available per verse via " <>
                 "`get_torah_weave` (e.g. reference='Genesis 1:1')"

      refute lookup("Psalm 22:1") =~ "Torah Weave"

      assert {:ok, %{hints: %{torah_weave: true}}} =
               LookupVerse.result(%{"reference" => "Ex 31:2"})
    end

    test "a quotation is cued once from either side" do
      ot = lookup("Psalm 40:6-8")
      assert occurrences(ot, "NT↔OT LXX-form quotation") == 1
      assert ot =~ "Psalm 40:6 quoted in **Hebrews 10:5-7** (vorlage_or_paraphrase)"
      assert occurrences(ot, "get_cross_references") == 1

      nt = lookup("Hebrews 10:5-7")
      assert occurrences(nt, "NT↔OT LXX-form quotation") == 1
      assert nt =~ "quotes **Psalm 40:6** in its LXX form"
    end

    test "a quotation that agrees with the MT is not called an LXX form" do
      mark = lookup("Mark 14:62")

      assert mark =~
               "*NT↔OT quotation: quotes **Daniel 7:13** (agrees_with_mt_and_theodotion)."

      refute mark =~ "LXX form"

      assert lookup("Matthew 26:64") =~
               "*NT↔OT LXX-form quotation: quotes **Daniel 7:13** in its LXX form (follows_old_greek)."
    end

    test "a variant is cued with its own verse inside a passage" do
      single = lookup("Psalm 40:6")
      assert single =~ "Textual variant catalogued for this verse (LXX_quoted_in_NT)"
      assert single =~ "`get_textual_variant` (reference='Psalm 40:6')"

      passage = lookup("Psalm 40:5-8")

      assert passage =~
               "Textual variants catalogued in this passage: Psalm 40:6 (LXX_quoted_in_NT). "

      refute passage =~ "reference='Psalm 40:5-8'"
      refute lookup("Psalm 40:7-8") =~ "Textual variant"
    end

    test "translation notes are cued apart from variants" do
      single = lookup("Psalm 82:6")
      assert single =~ "Translation and interpretation notes catalogued for this verse"
      refute single =~ "Textual variant"

      passage = lookup("Psalm 82")

      assert passage =~
               "catalogued in this passage: Psalm 82:1 (MT_preserved), Psalm 82:6 (MT_preserved). "

      refute passage =~ "Textual variant"
    end

    test "a verse with both a variant and notes is cued once, as a variant" do
      verse = lookup("Job 38:7")
      assert verse =~ "Textual variant catalogued for this verse (LXX_divergence)"
      refute verse =~ "no manuscript variant"

      passage = lookup("Job 38:6-7")
      assert passage =~ "Textual variants catalogued in this passage: Job 38:7 (LXX_divergence)"
      refute passage =~ "no manuscript variant"

      {:ok, %{hints: hints}} = LookupVerse.result(%{"reference" => "Job 38:6-7"})
      assert [%{reference: "Job 38:7", case_key: "LXX_divergence"}] = hints.variant_cases
      assert hints.interpretive_cases == []
    end

    test "result/1 carries the quotations with the side of them in the passage" do
      {:ok, %{hints: hints}} = LookupVerse.result(%{"reference" => "Daniel 7:13"})

      assert Enum.map(hints.quotations, &{&1.nt_display, &1.side, &1.follows_lxx}) == [
               {"Mark 14:62", :ot, false},
               {"Matthew 26:64", :ot, true},
               {"Matthew 24:30", :ot, true},
               {"Revelation 1:7", :ot, false}
             ]
    end
  end
end

defmodule Bezalel.Study.Tools.LookupVerseWithoutNotesTest do
  # Changes the packs directory, so not async.
  use ExUnit.Case, async: false

  alias Bezalel.Study.Tools.LookupVerse

  setup do
    fixtures = Application.fetch_env!(:bezalel_core, :packs_dir)
    dir = Path.join(System.tmp_dir!(), "bezalel-packs-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    File.ln_s!(Path.join(fixtures, "core.sqlite"), Path.join(dir, "core.sqlite"))
    Application.put_env(:bezalel_core, :packs_dir, dir)

    on_exit(fn ->
      Application.put_env(:bezalel_core, :packs_dir, fixtures)
      File.rm_rf!(dir)
    end)
  end

  test "without the notes pack the variant and quotation hints are left out, the rest kept" do
    assert {:ok, {:details, text, result}} =
             LookupVerse.run(%{"reference" => "Psalm 40:6"}, %{})

    refute text =~ "get_textual_variant"
    assert text =~ "`get_cross_references` (reference='Psalm 40:6')"
    assert %{variant_cases: [], quotations: []} = result.hints

    assert {:ok, {:details, torah, _}} = LookupVerse.run(%{"reference" => "Exodus 31:2"}, %{})
    assert torah =~ "`get_torah_weave` (reference='Exodus 31:2')"
  end
end
