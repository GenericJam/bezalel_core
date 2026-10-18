defmodule Bezalel.Study.SourceFiltersTest do
  # What the tools leave out when the user switches a source off, the
  # editorial verdicts (off by default) and the scripture labels.
  use ExUnit.Case, async: true

  alias Bezalel.Study.Ancient.Notes
  alias Bezalel.Study.{DB, Preferences, Sources}

  alias Bezalel.Study.Tools.{
    GetAneContext,
    GetBibleDictionary,
    GetKeyTerms,
    GetStudyNotes,
    GetTheologyContext,
    GetTorahWeave,
    LookupAncientSource,
    LookupVerse,
    SearchAncientSources
  }

  defp off(keys), do: Preferences.new(excluded_sources: keys)
  @verdicts Preferences.new(excluded_sources: [])
  @unlabelled Preferences.new(scripture_labels: false)

  defp text(tool, args, prefs) do
    assert {:ok, result} = tool.result(args, prefs)
    tool.render(result)
  end

  describe "ancient sources" do
    test "the default caveat is the provenance alone; the verdict comes with editorial verdicts" do
      default = text(LookupAncientSource, %{"citation" => "1 Enoch 1:9"}, %Preferences{})

      assert default =~
               "- Pseudepigrapha: Jewish pseudepigrapha (works written in the name of an " <>
                 "ancient figure). Jude 14–15 quotes 1 Enoch 1:9."

      refute default =~ "basis for doctrine"
      refute default =~ "Verdict"

      verdicts = text(LookupAncientSource, %{"citation" => "1 Enoch 1:9"}, @verdicts)

      assert verdicts =~
               "Jude 14–15 quotes 1 Enoch 1:9. Verdict (studybible-mcp): Outside the 66-book " <>
                 "canon; background only, never a basis for doctrine."

      philo = text(LookupAncientSource, %{"citation" => "Opif. 26"}, %Preferences{})
      assert philo =~ "- Philo: Not Scripture. A Jewish philosopher of Alexandria"
      refute philo =~ "incarnate"
      assert text(LookupAncientSource, %{"citation" => "Opif. 26"}, @verdicts) =~ "incarnate Son"
    end

    test "1 Enoch and 4 Ezra are labelled with the canons that hold them" do
      enoch = text(LookupAncientSource, %{"citation" => "1 Enoch 1:9"}, %Preferences{})

      assert enoch =~
               "*Scripture in the Ethiopian and Eritrean Orthodox Tewahedo canons and for " <>
                 "Beta Israel; not in other canons ·"

      refute enoch =~ "Not Scripture"

      ezra = text(LookupAncientSource, %{"citation" => "4 Ezra 7:28"}, %Preferences{})

      assert ezra =~
               "*Scripture in the Ethiopian Orthodox Tewahedo canon (as Ezra Sutuel); printed in " <>
                 "Slavonic Orthodox Bibles (as 3 Esdras) and the Vulgate's appendix (as 4 Esdras); " <>
                 "not in the Jewish, Catholic or Protestant canons ·"
    end

    test "without scripture labels no canon status is shown; the provenance stays" do
      josephus = text(LookupAncientSource, %{"citation" => "Ant. 18.117"}, @unlabelled)
      refute josephus =~ "Scripture"
      assert josephus =~ "*Jewish history (AD 93–94) · tier A · Niese Greek, Whiston English*"
      assert josephus =~ "- Josephus: A Jewish historian writing c. AD 75–100"

      enoch = text(LookupAncientSource, %{"citation" => "1 Enoch 1:9"}, @unlabelled)
      refute enoch =~ "Scripture in"
      refute enoch =~ "Tewahedo"
    end

    test "a ⚠ note keeps its provenance; its verdict and contrast field come with the verdicts" do
      default = text(LookupAncientSource, %{"citation" => "CD 6:19"}, %Preferences{})
      assert default =~ "the sect's claim to Jeremiah's new covenant."
      refute default =~ "Jesus speaks of"
      refute default =~ "Contrast:"

      verdicts = text(LookupAncientSource, %{"citation" => "CD 6:19"}, @verdicts)

      assert verdicts =~
               ~s|Verdict (studybible-mcp): Jesus speaks of "the new covenant in my blood"|

      assert verdicts =~ "(Contrast: Luke 22:20; Heb 8:8–13)"

      # 4 Ezra 7:28's interpolation note: the manuscript facts stay, the
      # Christian verdict goes.
      ezra = text(LookupAncientSource, %{"citation" => "4 Ezra 7:28"}, %Preferences{})
      assert ezra =~ "is a Latin Christian scribal change"
      assert ezra =~ "This Messiah dies with all flesh after 400 years."
      refute ezra =~ "dies no more"
      refute ezra =~ "Contrast: Rom 6:9"

      ezra_verdicts = text(LookupAncientSource, %{"citation" => "4 Ezra 7:28"}, @verdicts)

      assert ezra_verdicts =~
               "after 400 years. Verdict (studybible-mcp): Christ, raised, dies no more."

      assert ezra_verdicts =~ "Contrast: Rom 6:9"

      assert {:ok, %{passages: [passage]}} =
               LookupAncientSource.result(%{"citation" => "4 Ezra 7:28"}, %Preferences{})

      assert [%{"kind" => "interpolation"} = note] = passage.notes
      refute Map.has_key?(note, "contrast")
    end

    test "canon statements in notes follow the labels and name the canon; verdicts the verdicts" do
      jubilees = %{
        "citation" => "CD 16:2–4",
        "kind" => "caution",
        "contrast" => "Col 2:16–17; Gal 4:10",
        "aligned" => "",
        "note" =>
          ~s|Lines 3–4 name "the book of the divisions of the times into their jubilees and | <>
            ~s|their weeks" (Jubilees) as the exact authority on Israel's times. Jubilees, with | <>
            "its 364-day calendar, is not Scripture."
      }

      labelled = Notes.shown(jubilees, %Preferences{})
      refute labelled["note"] =~ "is not Scripture"

      assert labelled["note"] =~
               "as the exact authority on Israel's times. Jubilees is Scripture in the " <>
                 "Ethiopian and Eritrean Orthodox Tewahedo canons and for Beta Israel"

      refute Map.has_key?(labelled, "contrast")

      unlabelled = Notes.shown(jubilees, @unlabelled)
      refute unlabelled["note"] =~ "Scripture"
      assert unlabelled["note"] =~ "(Jubilees, with its 364-day calendar)"

      giants = %{
        "citation" => "1 Enoch 15:8–12",
        "kind" => "caution",
        "contrast" => "",
        "aligned" => "Gen 6:4; Num 13:33",
        "note" =>
          "Evil spirits as the spirits of the giants: a Second Temple explanation of demons, " <>
            "adopted by Heiser. Scripture names the Nephilim but is silent on where demons " <>
            "come from: compatible with, not taught by, Scripture."
      }

      assert Notes.shown(giants, %Preferences{})["note"] ==
               "Evil spirits as the spirits of the giants: a Second Temple explanation of " <>
                 "demons, adopted by Heiser."

      assert Notes.shown(giants, %Preferences{})["aligned"] == "Gen 6:4; Num 13:33"
      assert Notes.shown(giants, @verdicts)["note"] =~ "Verdict (studybible-mcp): Scripture names"
    end

    test "every fixture note was audited; an unknown contrast note needs the verdicts" do
      {:ok, notes} =
        DB.with_pack(:ancient, &DB.all(&1, "SELECT note FROM ancient_source_notes"))

      assert notes != []
      for %{"note" => note} <- notes, do: assert(Notes.audited?(note), note)

      unknown = %{"citation" => "X 1", "kind" => "contrast", "note" => "A new verdict."}
      assert Notes.shown(unknown, %Preferences{}) == nil
      assert Notes.shown(unknown, @verdicts)["note"] == "A new verdict."

      factual = %{"citation" => "X 1", "kind" => "gap", "note" => "A new gap."}
      assert Notes.shown(factual, %Preferences{})["note"] == "A new gap."
    end

    test "a switched-off corpus: refused when named, left out of 'all', not the default" do
      prefs = off(["ancient:josephus"])

      assert {:error, "The user has switched off Josephus" <> _} =
               LookupAncientSource.result(%{"citation" => "Ant. 18.117"}, prefs)

      assert {:error, "The user has switched off Josephus" <> _} =
               LookupAncientSource.result(
                 %{"citation" => "Ant. 18.117", "corpus" => "josephus"},
                 prefs
               )

      assert {:error, "The user has switched off Josephus" <> _} =
               SearchAncientSources.result(%{"query" => "Herod", "corpus" => "josephus"}, prefs)

      assert {:ok, all} =
               SearchAncientSources.result(%{"query" => "God", "corpus" => "all"}, prefs)

      assert all.passages != []
      refute Enum.any?(all.passages, &(&1.corpus == "josephus"))

      assert {:ok, %{corpus: "all"}} = SearchAncientSources.result(%{"query" => "God"}, prefs)

      assert {:ok, with_josephus} =
               SearchAncientSources.result(
                 %{"query" => "God", "corpus" => "all", "limit" => 20},
                 %Preferences{}
               )

      assert Enum.any?(with_josephus.passages, &(&1.corpus == "josephus"))
    end

    test "the default number of passages is the user's limit, held to the tool's maximum" do
      count = fn prefs ->
        {:ok, r} = SearchAncientSources.result(%{"query" => "God", "corpus" => "all"}, prefs)
        length(r.passages)
      end

      assert count.(Preferences.new(limit: 2)) == 2
      assert count.(%Preferences{}) == 8
      assert count.(Preferences.new(limit: 50)) <= 20
    end
  end

  describe "every source of a tool switched off" do
    test "the tool says so instead of answering with nothing" do
      ancient = for k <- Sources.keys(), String.starts_with?(k, "ancient:"), do: k
      theologians = for k <- Sources.keys(), String.starts_with?(k, "theology:"), do: k
      notes = ~w(notes:study_notes notes:translation_notes_uw notes:translation_notes_sil)

      for {tool, args, keys} <- [
            {SearchAncientSources, %{"query" => "God", "corpus" => "all"}, ancient},
            {SearchAncientSources, %{"query" => "God"}, ancient},
            {LookupAncientSource, %{"citation" => "Ant. 18.117"}, ancient},
            {GetTheologyContext, %{"reference" => "Psalm 82:6"}, theologians},
            {GetTheologyContext, %{}, theologians},
            {GetStudyNotes, %{"reference" => "John 3:16"}, notes}
          ] do
        assert {:error, message} = tool.result(args, off(keys)), inspect({tool, args})
        assert message =~ "The user has switched off all the sources this tool reads ("
        assert message =~ "don't supply them from memory"
        assert {:ok, _} = tool.result(args, off(tl(keys))), inspect({tool, args})
      end

      assert {:error, message} = GetStudyNotes.result(%{"reference" => "John 3:16"}, off(notes))

      assert message =~
               "(Tyndale Study Notes, unfoldingWord Translation Notes, SIL Translator Notes)"
    end
  end

  describe "notes" do
    test "theologians switched off: their entries and themes are gone, naming one is an error" do
      prefs = off(["theology:stott"])

      assert {:ok, %{entries: entries}} =
               GetTheologyContext.result(%{"theme" => "atonement_models", "limit" => 20}, prefs)

      assert entries != []
      assert entries |> Enum.map(& &1.source_author) |> Enum.uniq() == ["synthesis"]

      assert {:error, "The user has switched off John Stott" <> _} =
               GetTheologyContext.result(%{"author" => "stott"}, prefs)

      assert {:ok, %{themes: themes}} =
               GetTheologyContext.result(%{}, off(["theology:stott", "theology:synthesis"]))

      refute "atonement_models" in Enum.map(themes, & &1.key)
    end

    test "study-note types switched off are left out" do
      args = %{"reference" => "John 3:16"}
      assert {:ok, %{notes: all}} = GetStudyNotes.result(args, %Preferences{})
      assert "translation_notes_uw" in Enum.map(all, & &1.resource_type)

      assert {:ok, %{notes: some}} =
               GetStudyNotes.result(args, off(["notes:translation_notes_uw"]))

      assert some != []
      refute "translation_notes_uw" in Enum.map(some, & &1.resource_type)
    end

    test "single-source tools refuse when their source is off" do
      for {tool, args, key} <- [
            {GetBibleDictionary, %{"topic" => "Bezalel"}, "notes:dictionary"},
            {GetKeyTerms, %{"term" => "grace"}, "notes:key_terms"},
            {GetAneContext, %{"reference" => "Exodus 31"}, "ane:context"},
            {GetTorahWeave, %{"reference" => "Exodus 31:2"}, "method:torah_weave"}
          ] do
        assert {:error, "The user has switched off " <> _} = tool.result(args, off([key])),
               inspect(tool)

        assert {:ok, _} = tool.result(args, %Preferences{})
      end
    end
  end

  describe "lookup_verse" do
    test "the genre guidance is off by default and credited when on; the Torah weave hint follows its source" do
      args = %{"reference" => "Exodus 31:3"}

      default = text(LookupVerse, args, Preferences.new(translation: "bsb"))
      refute default =~ "## Genre:"
      refute default =~ "Fee & Stuart"
      assert default =~ "`get_torah_weave`"

      on = text(LookupVerse, args, Preferences.new(translation: "bsb", excluded_sources: []))

      assert on =~
               "Genre guidance after Fee & Stuart, *How to Read the Bible for All Its Worth* " <>
                 "(evangelical):\n\n## Genre: Old Testament Narratives"

      prefs = Preferences.new(translation: "bsb", excluded_sources: ["method:torah_weave"])

      assert {:ok, result} = LookupVerse.result(args, prefs)
      assert result.genre_guidance
      refute result.hints.torah_weave
      off = LookupVerse.render(result)
      refute off =~ "get_torah_weave"
      assert off =~ "`get_cross_references`"
    end
  end
end
