defmodule Bezalel.Study.TextToolsTest do
  # Ported from studybible-mcp's tests/test_tool_handlers.py (get_torah_weave),
  # test_textual_variants.py, test_variant_witnesses.py and
  # test_biblical_versions.py, against the fixture packs (all textual-variant
  # cases and quotation hints; the Torah weave units over Genesis 1-2 and
  # Exodus 31; the MT and LXX of make_fixtures.py's chapters and
  # EXTRA_VERSES / LXX_EXTRA).
  use ExUnit.Case, async: true

  alias Bezalel.Study.{Citation, Preferences}
  alias Bezalel.Study.Tools.{CompareBiblicalVersions, GetTextualVariant, GetTorahWeave}

  defp ok(tool, args), do: tool |> cited(args) |> elem(0)

  # The Markdown and the citations a tool returns with it.
  defp cited(tool, args) do
    assert {:ok, {:details, text, %{citations: citations}}} = tool.run(args, %{})
    {text, citations}
  end

  @leon_levy "https://www.deadseascrolls.org.il/explore-the-archive/manuscript/"

  defp error(tool, args) do
    assert {:error, text} = tool.run(args, %{})
    text
  end

  # The text from `heading` to the next heading of the same or a higher level.
  defp section(text, heading) do
    [_, rest] = String.split(text, heading <> "\n", parts: 2)
    level = heading |> String.split(" ") |> hd()
    hashes = String.length(level)

    rest
    |> String.split("\n")
    |> Enum.take_while(fn line ->
      case Regex.run(~r/^(#+) /, line) do
        [_, marks] -> String.length(marks) > hashes
        nil -> true
      end
    end)
    |> Enum.join("\n")
  end

  defp occurrences(text, part), do: text |> String.split(part) |> Enum.count() |> Kernel.-(1)

  defp cells(text), do: for([_, label] <- Regex.scan(~r/Cell (\w+)\*\*/, text), do: label)

  describe "get_torah_weave" do
    test "a cell's unit, position and partners by direction" do
      text = ok(GetTorahWeave, %{"reference" => "Genesis 1:1"})

      assert text =~ ~r/\A## Torah Weave for Genesis 1:1\n/
      assert text =~ ~s[### Unit 1 · "Creation" (Genesis 1:1-2:3)]
      assert text =~ "**Format**: 3x2 · **Type**: CL — Closure (provides envelope closure)"
      assert text =~ "**Cell position**: `1A` — row 1, column A\n"
      assert text =~ "**Cell verse range**: Genesis 1:1\n"
      assert cells(section(text, "#### ⇄ Horizontal weave partners (same row)")) == ["1B"]
      assert text =~ "- **Cell 1B** — Genesis 1:2"
      assert cells(section(text, "#### ↕ Vertical weave partners (same column)")) == ["2A", "3A"]
      refute text =~ "Sibling cells (same row + column)"
      assert text =~ "### How to read Torah Weave partners"

      {:ok, %{matches: [match]}} = GetTorahWeave.result(%{"reference" => "Genesis 1:1"})
      assert %{unit: %{id: 1, title: "Creation", type: "CL"}, cell: %{label: "1A"}} = match
      assert Enum.map(match.vertical, & &1.label) == ["2A", "3A"]
    end

    test "a subdivided cell has siblings, and says when it has no partner in a direction" do
      text = ok(GetTorahWeave, %{"reference" => "Genesis 1:26"})

      assert text =~ "**Cell position**: `2Bc` — row 2, column B (subdivision c)"
      assert text =~ "- **Cell 2Ac** (subdivision c) — Genesis 1:11-13"
      assert text =~ "*(none — this cell has no column partner)*"

      assert cells(section(text, "#### ↔ Sibling cells (same row + column)")) ==
               ["2B", "2Ba", "2Bb"]
    end

    test "a Torah verse no unit covers is a result; other references are errors" do
      assert ok(GetTorahWeave, %{"reference" => "Exodus 3:1"}) ==
               "No Torah Weave unit contains Exodus 3:1. " <>
                 "Torah Weave data covers Genesis–Deuteronomy only."

      for reference <- ["Matthew 5:1", "Genesis"] do
        assert error(GetTorahWeave, %{"reference" => reference}) ==
                 "No Torah Weave unit contains #{reference}. " <>
                   "Torah Weave data covers Genesis–Deuteronomy only."
      end

      assert error(GetTorahWeave, %{"reference" => ""}) ==
               "Please provide a Bible reference in Genesis–Deuteronomy."
    end

    test "each unit cites its page at chaver.com" do
      {text, citations} = cited(GetTorahWeave, %{"reference" => "Genesis 1:1"})
      url = "https://chaver.com/torah-weave/Genesis/genesis-unit-1/genesis-unit-1"

      assert section(text, ~s[### Unit 1 · "Creation" (Genesis 1:1-2:3)]) =~
               "\nSource: [Genesis unit 1: Creation](#{url})\n"

      assert [%Citation{work: "torah_weave", url: ^url}] = citations
      assert text =~ "*Source: Moshe Kline, Woven Torah hypothesis (chaver.com, CC BY 4.0)*"
    end
  end

  describe "get_textual_variant" do
    test "witnesses are kept on their reading, citations, indirect evidence and absences apart" do
      psalm = ok(GetTextualVariant, %{"reference" => "Psalm 40:6"})
      assert section(psalm, "#### LXX_quoted_in_NT") =~ "**LXX** (~150 BCE)"
      refute section(psalm, "#### LXX_quoted_in_NT") =~ "Hebrews 10:5-7"

      assert section(psalm, "### NT citation evidence") =~
               "- **Hebrews 10:5-7** (~65 CE) — quotes the LXX_quoted_in_NT reading"

      assert psalm =~ "**Not preserved in:** DSS\n"

      jeremiah = ok(GetTextualVariant, %{"reference" => "Jeremiah 33:14"})
      assert section(jeremiah, "#### Masoretic Text") =~ "Masoretic Text"
      refute section(jeremiah, "#### LXX_omission") =~ "4QJer^b"
      assert section(jeremiah, "### Indirect evidence") =~ "4QJer^b"

      {:ok, %{cases: [jer]}} = GetTextualVariant.result(%{"reference" => "Jeremiah 33:14"})
      readings = Map.new(jer.readings, &{&1.key, &1})

      assert [%{witness: "Masoretic Text", support: "supports_long_form"}] =
               readings["mt"].witnesses

      assert Enum.map(jer.indirect_evidence, & &1.witness) == [
               "4QJer^b (short Vorlage elsewhere in Jer)",
               "4QJer^d (short Vorlage elsewhere in Jer)"
             ]
    end

    test "uncited judgments are an unsourced summary, not critical judgments" do
      text = ok(GetTextualVariant, %{"reference" => "Deuteronomy 32:8"})

      refute text =~ "### Critical judgments"

      assert section(
               text,
               "### Unsourced dataset summary (not verified against published text-critical scholarship)"
             ) =~ "- "
    end

    test "a variant comes first and the notes at the same verse point back to it" do
      text = ok(GetTextualVariant, %{"reference" => "Job 38:7"})

      assert text =~ ~r/\A# Textual variant record for Job 38:7\n/
      [variant, notes] = String.split(text, "## Translation and interpretation notes at Job.38.7")
      assert variant =~ "## Variant at Job.38.7"

      assert section(text, "#### Masoretic Text") =~
               "**Masoretic Text** (~900 CE) (dataset label: `supports_mt`)"

      assert text =~
               "**Case key:** LXX_divergence\n**Significance classification:** minor_textual"

      refute text =~ "Not a manuscript variant"
      assert notes =~ "The textual evidence at this verse is in the variant record above."
      refute notes =~ "### Text (Masoretic Text)"
      refute notes =~ "Witnesses agreeing with this text"
      assert notes =~ "### Author-specific claims"
    end

    test "agreed-text notes have their banner and their witnesses" do
      text = ok(GetTextualVariant, %{"reference" => "Psalm 82:1"})

      assert text =~ ~r/\A# Translation and interpretation notes for Psalm 82:1\n/

      assert text =~
               "*Not a manuscript variant: the witnesses agree with the Masoretic Text here."

      assert text =~
               "**Witnesses agreeing with this text:** Masoretic Text (~900 CE), LXX (~250 BCE)"

      refute text =~ "## Variant at"
      refute text =~ "dataset label"
    end

    test "an NT verse reaches the cases of the OT verse it quotes, with only its own alignment" do
      text = ok(GetTextualVariant, %{"reference" => "Matthew 26:64"})

      assert text =~ ~r/\A# Textual variant record for Matthew 26:64\n/
      assert text =~ "## Variant at Dan.7.13"
      assert text =~ "## Translation and interpretation notes at Dan.7.13"
      [_, alignment] = String.split(text, "## NT quotation alignment")
      assert alignment =~ "- **Matthew 26:64** quotes **Daniel 7:13** — *follows_old_greek*: "
      assert occurrences(alignment, "quotes **Daniel 7:13**") == 1

      dan = ok(GetTextualVariant, %{"reference" => "Daniel 7:13"})
      [_, all] = String.split(dan, "## NT quotation alignment")
      assert occurrences(all, "quotes **Daniel 7:13**") == 4
    end

    test "nothing catalogued is a result; a missing or non-verse reference is an error" do
      assert ok(GetTextualVariant, %{"reference" => "Genesis 1:1"}) ==
               "No textual-variant case or NT quotation alignment is catalogued for Genesis 1:1."

      assert error(GetTextualVariant, %{"reference" => "Psalm 40"}) =~
               "'Psalm 40' is not a single-verse reference."

      assert error(GetTextualVariant, %{"reference" => " "}) ==
               "Please provide a verse reference (OT or NT)."
    end

    test "the HLT decisions are an unpublished AI-assisted draft citing the originals, never Heiser's" do
      {text, citations} = cited(GetTextualVariant, %{"reference" => "Deuteronomy 32:8"})
      deutj = @leon_levy <> "4Q37-1"

      decisions = section(text, "### Translation decisions")

      assert decisions =~
               "- **Unpublished draft rendering (AI-assisted), not Heiser's:** " <>
                 "according to the number of the sons of God"

      assert decisions =~
               "  - Source: unpublished draft rendering (AI-assisted), not Heiser's; original: " <>
                 "[Hebrew (MT)](https://www.stepbible.org/?q=version=THOT@reference=Deu.32.8), " <>
                 "[Greek (LXX)](https://www.stepbible.org/?q=version=LXX@reference=Deu.32.8), " <>
                 "[4Q37 (4QDeutj)](#{deutj})"

      assert [%Citation{translation: :unpublished_draft, url: nil, original: original}] =
               Enum.filter(citations, &(&1.work == "hlt"))

      assert Enum.map(original, & &1.label) == ["Hebrew (MT)", "Greek (LXX)", "4Q37 (4QDeutj)"]

      # The scroll witness itself cites its manuscript.
      assert section(text, "#### DSS_4QDeutj") =~
               "- **4QDeutj** (~150-100 BCE) (dataset label: `supports_variant`)\n" <>
                 "  - Source: [4Q37 (4QDeutj)](#{deutj})"

      assert %Citation{translation: :assistant} = Enum.find(citations, &(&1.url == deutj))

      {:ok, %{cases: [deu]}} = GetTextualVariant.result(%{"reference" => "Deuteronomy 32:8"})

      assert [%{draft: true, translation: "Unpublished draft rendering" <> _}] =
               deu.translation_decisions

      # Nowhere is the draft Heiser's, nor "the HLT" (its rationales' name for it).
      for reference <- ["Deuteronomy 32:8", "Job 38:7", "Psalm 82:1", "Psalm 40:6", "Daniel 7:13"] do
        text = ok(GetTextualVariant, %{"reference" => reference})
        refute text =~ "Heiser Literal Translation", reference
        refute text =~ "HLT", reference
        assert text =~ "not Heiser's:**", reference
      end

      assert ok(GetTextualVariant, %{"reference" => "Job 38:7"}) =~
               "  - Rationale: The draft makes"
    end
  end

  describe "compare_biblical_versions" do
    test "the MT and the LXX share one canonical header, each with its edition reference" do
      for {reference, mt, lxx} <- [
            {"Psalm 40:6", "Psa.40.7", "Psa.39.7"},
            {"Psalm 82:6", "Psa.82.6", "Psa.81.6"}
          ] do
        {:ok, result} = CompareBiblicalVersions.result(%{"reference" => reference})

        assert Enum.map(result.rows, &{&1.version, &1.edition_reference}) == [
                 {"MT", mt},
                 {"LXX", lxx}
               ]

        text = CompareBiblicalVersions.render(result)
        assert occurrences(text, "\n### ") == 1
        assert text =~ "STEPBible word glosses (interlinear, not a translation)"

        assert text =~ "TAHOT English/Hebrew versification" ==
                 (mt != hd(result.rows).canonical_reference)
      end
    end

    test "reference forms: ranges across chapters, en dashes, whole chapters, compact names" do
      canonical = fn reference ->
        {:ok, result} = CompareBiblicalVersions.result(%{"reference" => reference})
        Enum.map(result.rows, & &1.canonical_reference)
      end

      assert canonical.("Psalm 82:5-6") == ["Psa.82.5", "Psa.82.5", "Psa.82.6", "Psa.82.6"]
      assert canonical.("Psalm 82:5–6") == canonical.("Psalm 82:5-6")
      assert canonical.("Ps82:6") == ["Psa.82.6", "Psa.82.6"]
      assert Enum.count(canonical.("Psalm 82")) == 16
    end

    test "why nothing matched" do
      assert error(CompareBiblicalVersions, %{"reference" => "Luke 4:9"}) =~
               "Old Testament and Septuagint books only"

      assert error(CompareBiblicalVersions, %{"reference" => "Psalm eighty-two"}) =~
               "Could not parse"

      assert error(CompareBiblicalVersions, %{"reference" => "Psalm 82:8-1"}) =~ "Could not parse"

      for numbering <- ["canonical", "lxx"] do
        assert error(CompareBiblicalVersions, %{
                 "reference" => "Psalm 1:99999999999999999999",
                 "numbering" => numbering
               }) =~ "Could not parse 'Psalm 1:99999999999999999999'"
      end

      assert error(CompareBiblicalVersions, %{"reference" => "Hezekiah 1:1"}) =~
               "'Hezekiah' is not a book covered by compare_biblical_versions."

      assert ok(CompareBiblicalVersions, %{"reference" => "Psalm 30:1"}) ==
               "No MT or LXX or DSS text found for Psalm 30:1 (canonical MT/English numbering)."

      assert ok(CompareBiblicalVersions, %{
               "reference" => "Psalm 30:1",
               "versions" => ["MT", "LXX"]
             }) == "No MT or LXX text found for Psalm 30:1 (canonical MT/English numbering)."

      assert ok(CompareBiblicalVersions, %{"reference" => "Psalm 82:1a"}) =~ "No MT or LXX"
    end

    test "argument errors" do
      assert error(CompareBiblicalVersions, %{"reference" => ""}) ==
               "Please provide a verse reference (e.g., 'Psalm 24:1')."

      for versions <- [[], "MT", nil] do
        assert error(CompareBiblicalVersions, %{
                 "reference" => "Psalm 82:6",
                 "versions" => versions
               }) ==
                 "'versions' must be a non-empty list containing MT, LXX and/or DSS."
      end

      assert error(CompareBiblicalVersions, %{
               "reference" => "Psalm 82:6",
               "versions" => ["mt", "Vulgate"]
             }) ==
               "Unsupported biblical version(s): VULGATE. Use MT, LXX and/or DSS."

      assert error(CompareBiblicalVersions, %{"reference" => "Psalm 82:6", "numbering" => "Greek"}) =~
               "Unsupported numbering 'greek'."
    end

    test "LXX-only verses: listed under canonical numbering, shown under Greek numbering" do
      text = ok(CompareBiblicalVersions, %{"reference" => "Daniel 3:25"})
      {:ok, result} = CompareBiblicalVersions.result(%{"reference" => "Daniel 3:25"})

      assert Enum.map(result.rows, &{&1.version, &1.edition_reference}) ==
               [{"MT", "Dan.3.25"}, {"LXX", "Dan.3.92"}, {"LXX", "Dan.3.92"}]

      assert Enum.map(result.lxx_only, & &1.edition_reference) == ["Dan.3.25", "Dan.3.25"]
      refute text =~ "Αζαριας"
      assert text =~ "**English:** not available for this edition."
      assert text =~ "Request numbering='lxx' to view them."

      greek = ok(CompareBiblicalVersions, %{"reference" => "Daniel 3:25", "numbering" => "lxx"})
      assert greek =~ "## Biblical Version Comparison: Daniel 3:25 (Septuagint edition numbering)"
      assert greek =~ "### Dan.3.25 (LXX-only, no MT counterpart)"
      assert occurrences(greek, " (not in the Hebrew Bible)\n") == 2
      assert greek =~ "**English (KJV Apocrypha):** Then Azarias stood up"

      assert greek =~
               "*Canon: the Prayer of Azariah and Song of the Three (Dan 3:24–90) are in the " <>
                 "Catholic and Orthodox canons, not the Jewish or Protestant ones.*"

      refute greek =~ "Brenton's English:"
    end

    test "an LXX-only book uses Greek numbering and needs the LXX" do
      text = ok(CompareBiblicalVersions, %{"reference" => "Tobit 1:1"})

      assert text =~
               "#### LXX Rahlfs Septuagint (1935) · Tob.1.1 (mapping: lxx-only) (not in the Hebrew Bible)"

      assert text =~ "**English (KJV Apocrypha):** "
      assert text =~ "English: KJV (Authorized Version) Apocrypha, lightly adapted by Brenton."

      assert text =~
               "*Canon: Tobit is in the Catholic and Orthodox canons, not the Jewish or Protestant ones.*"

      # The Protestant verdict is an editorial source, off by default.
      refute text =~ "Westminster"

      assert text =~ ~r/\*KJV Apocrypha English: [^\n]*\*\z/
      refute text =~ "Brenton's English:"

      assert error(CompareBiblicalVersions, %{"reference" => "Tobit 1:1", "versions" => ["MT"]}) ==
               "Tobit 1:1 is in a Septuagint-only book with no Masoretic Text; include 'LXX' in versions."
    end

    test "the canon line follows the scripture labels; the Westminster line the editorial verdicts" do
      args = %{"reference" => "Tobit 1:1"}
      render = &CompareBiblicalVersions.render(elem(CompareBiblicalVersions.result(args, &1), 1))

      unlabelled = render.(Preferences.new(scripture_labels: false))
      refute unlabelled =~ "*Canon:"
      refute unlabelled =~ "Westminster"
      # The provenance stays.
      assert unlabelled =~ "(not in the Hebrew Bible)"
      assert unlabelled =~ "*KJV Apocrypha English: "

      verdicts = render.(Preferences.new(excluded_sources: []))
      assert verdicts =~ "*Canon: Tobit is in the Catholic and Orthodox canons"

      assert verdicts =~
               "*Verdict (studybible-mcp): Tobit is not in the Protestant canon " <>
                 "(cf. Westminster Confession 1.3); background only.*"
    end

    test "Brenton's differing Greek is flagged; matching Greek gets only the standing note" do
      flagged =
        ok(CompareBiblicalVersions, %{"reference" => "Deuteronomy 32:43", "versions" => ["LXX"]})

      assert flagged =~ "**Warning: Brenton's English below translates a different Greek text.**"
      assert flagged =~ "**Brenton's Greek (the text his English translates):** "

      assert flagged =~
               "- Brenton's Greek: public domain. https://ebible.org/details.php?id=grcbrent"

      [warning, english, note] =
        Enum.map(
          ["Warning", "**English", "*Brenton's English:"],
          &(:binary.match(flagged, &1) |> elem(0))
        )

      assert warning < english and english < note

      without_greek =
        ok(CompareBiblicalVersions, %{
          "reference" => "Deuteronomy 32:43",
          "versions" => ["LXX"],
          "include_original" => false
        })

      assert without_greek =~ "Warning"
      refute without_greek =~ "Brenton's Greek (the text"

      {:ok, %{rows: [row]}} =
        CompareBiblicalVersions.result(%{"reference" => "Psalm 40:6", "versions" => ["LXX"]})

      assert %{status: :differs, difference: "Brenton's Greek reads σῶμα for ὠτία"} =
               row.brenton

      matching =
        ok(CompareBiblicalVersions, %{"reference" => "Psalm 82:6", "versions" => ["LXX"]})

      refute matching =~ "Warning"
      assert occurrences(matching, "*Brenton's English: ") == 1
      refute matching =~ "Apocrypha"
    end

    test "the original text and morphology flags" do
      compact =
        ok(CompareBiblicalVersions, %{"reference" => "Psalm 82:6", "include_original" => false})

      refute compact =~ "**Greek:**"
      refute compact =~ "Morphology"
      assert compact =~ "#### LXX Rahlfs Septuagint (1935) · Psa.81.6 (mapping: tvtms)"
      assert compact =~ "- LXX Rahlfs Septuagint (1935) (Greek): CC BY 4.0 (morphology);"
      assert compact =~ "TVTMS (Tyndale Versification Traditions Mapping System)"

      detailed =
        ok(CompareBiblicalVersions, %{"reference" => "Psalm 82:6", "include_morphology" => true})

      assert detailed =~ "**Morphology:**"
      assert detailed =~ "- **ἐγὼ** ("
      assert detailed =~ " (H0559; HVqp1cs) — I said"
    end

    test "more than ten verses are cut, naming where to continue" do
      text = ok(CompareBiblicalVersions, %{"reference" => "Genesis 1"})

      assert text =~
               "*Showing the first 10 of 31 verses. Continue from 'Genesis 1:11' in another call.*"

      {:ok, result} = CompareBiblicalVersions.result(%{"reference" => "Genesis 1"})
      assert result.rows |> Enum.map(& &1.canonical_reference) |> Enum.uniq() |> length() == 10

      {:ok, greek} =
        CompareBiblicalVersions.result(%{"reference" => "Genesis 1", "numbering" => "lxx"})

      assert greek.cap_note =~ "Continue from Gen.1.11 (numbering='lxx') in another call."

      {:ok, short} = CompareBiblicalVersions.result(%{"reference" => "Psalm 82"})
      assert short.cap_note == ""
    end

    test "each row cites its edition: the MT and LXX on STEP, Brenton at eBible" do
      {text, citations} = cited(CompareBiblicalVersions, %{"reference" => "Daniel 7:13"})
      step = "https://www.stepbible.org/?q=version="
      mt = step <> "THOT@reference=Dan.7.13"
      lxx = step <> "LXX@reference=Dan.7.13"
      brenton = "https://ebible.org/eng-Brenton/DAG07.htm#V13"

      assert section(text, "#### MT STEPBible TAHOT / Westminster Leningrad Codex · Dan.7.13") =~
               "\nSource: [Daniel 7:13 (Hebrew)](#{mt})\n"

      # The Old Greek has no English here: any English is the assistant's.
      assert section(text, "#### LXX Rahlfs Septuagint (1935), Old Greek · Dan.7.13") =~
               "\nSource: [Daniel 7:13 (LXX)](#{lxx}) (original text: any English you give for it is your own"

      assert section(text, "#### LXX Rahlfs Septuagint (1935), Theodotion · Dan.7.13") =~
               "\nSource: [Daniel 7:13 (LXX)](#{lxx}) · [Daniel 7:13 (Brenton)](#{brenton})\n"

      assert [
               %Citation{work: "step", url: ^mt},
               %Citation{work: "lxx", url: ^lxx, translation: :assistant},
               %Citation{work: "brenton", url: ^brenton}
             ] = citations

      assert text =~ "**Sources**\n- MT STEPBible TAHOT"
    end
  end
end

defmodule Bezalel.Study.TextToolsWithoutLxxTest do
  # Changes the packs directory, so not async.
  use ExUnit.Case, async: false

  alias Bezalel.Study.Tools.CompareBiblicalVersions

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

  test "without the lxx pack the LXX is the pack error, but the MT alone still works" do
    assert {:error, message} = CompareBiblicalVersions.run(%{"reference" => "Psalm 82:6"}, %{})
    assert message =~ "The lxx study pack (Septuagint) isn't downloaded"

    assert {:ok, %{rows: [%{version: "MT", edition_reference: "Psa.82.6"}]}} =
             CompareBiblicalVersions.result(%{"reference" => "Psalm 82:6", "versions" => ["MT"]})

    assert {:error, _} =
             CompareBiblicalVersions.run(
               %{"reference" => "Psalm 81:6", "versions" => ["MT"], "numbering" => "lxx"},
               %{}
             )
  end
end
