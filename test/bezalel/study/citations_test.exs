defmodule Bezalel.Study.CitationsTest do
  # The examples are the URLs checked against the live sites on 2026-10-18
  # (decisions/2026-10-18-sources.md).
  use ExUnit.Case, async: true

  alias Bezalel.Study.{Citation, Citations}

  describe "scripture" do
    test "NET verse pages use the English book name with + for spaces" do
      assert Citations.net("Jhn.3.16").url == "https://netbible.org/bible/John+3:16"
      assert Citations.net("1Sa.3.4").url == "https://netbible.org/bible/1+Samuel+3:4"
      assert Citations.net("Sng.1.1").url == "https://netbible.org/bible/Song+of+Solomon+1:1"
      assert Citations.net({"Jhn", 3, 16}).label == "John 3:16"
    end

    test "a Psalm superscription links its chapter's first verse" do
      assert Citations.net("Psa.3.0").url == "https://netbible.org/bible/Psalms+3:1"
    end

    test "BSB verses at Bible Hub, with its slugs" do
      assert Citations.bsb("Jhn.3.16").url == "https://biblehub.com/john/3-16.htm"
      assert Citations.bsb("1Sa.3.4").url == "https://biblehub.com/1_samuel/3-4.htm"
      assert Citations.bsb("Sng.1.1").url == "https://biblehub.com/songs/1-1.htm"
      assert Citations.bsb("Psa.3.1").url == "https://biblehub.com/psalms/3-1.htm"
    end

    test "scripture picks the translation, and the original for a gloss-only verse" do
      assert Citations.scripture("Jhn.3.16", "net").work == "net"
      assert Citations.scripture("Jhn.3.16", %{key: "bsb"}).work == "bsb"
      assert Citations.scripture("Jhn.3.16", nil).work == "step"
    end

    test "STEP's Hebrew for the OT and Greek for the NT; superscriptions as verse 1" do
      assert Citations.step("Deu.32.8").url ==
               "https://www.stepbible.org/?q=version=THOT@reference=Deu.32.8"

      assert Citations.step("Jhn.3.16").url ==
               "https://www.stepbible.org/?q=version=THGNT@reference=Jhn.3.16"

      assert Citations.step("Psa.3.0").url ==
               "https://www.stepbible.org/?q=version=THOT@reference=Psa.3.1"
    end

    test "the Septuagint on STEP; with no English it is the assistant's to translate" do
      published = Citations.lxx("Deu.32.8")
      assert published.url == "https://www.stepbible.org/?q=version=LXX@reference=Deu.32.8"
      assert published.translation == :published

      bare = Citations.lxx("Deu.32.8", english: false)
      assert bare.translation == :assistant
      assert bare.original == [%{label: bare.label, url: bare.url}]
    end

    test "Brenton at eBible: two-digit chapters, three for Psalms, his own book files" do
      assert Citations.brenton("Gen.1.1").url == "https://ebible.org/eng-Brenton/GEN01.htm#V1"
      assert Citations.brenton("Psa.3.2").url == "https://ebible.org/eng-Brenton/PSA003.htm#V2"
      assert Citations.brenton("Dan.1.1").url == "https://ebible.org/eng-Brenton/DAG01.htm#V1"
      assert Citations.brenton("2Es.12.1").url == "https://ebible.org/eng-Brenton/NEH02.htm#V1"
      assert Citations.brenton("2Es.3.1").url == "https://ebible.org/eng-Brenton/EZR03.htm#V1"
    end
  end

  describe "lexicons" do
    test "BDB and Strong's at Bible Hub, without padding or sense letters" do
      assert Citations.bdb("H0430G", "אֱלֹהִים").url == "https://biblehub.com/bdb/430.htm"
      assert Citations.bdb("H0430", "אֱלֹהִים").label == "BDB H430 אֱלֹהִים"
      assert Citations.strongs("H0430").url == "https://biblehub.com/hebrew/430.htm"
      assert Citations.strongs("G0026").url == "https://biblehub.com/greek/26.htm"
    end

    test "LSJ by lemma at lsj.gr" do
      assert URI.decode(Citations.lsj("G0026", "ἀγάπη").url) == "https://lsj.gr/wiki/ἀγάπη"
    end

    test "STEP's brief lexicon by padded Strong's number" do
      assert Citations.step_lexicon("H430").url == "https://www.stepbible.org/?q=strong=H0430"
    end

    test "Abbott-Smith is a book, linked at its entry's page of the Internet Archive scan" do
      c = Citations.abbott_smith("G0026", "ἀγάπη")
      assert c.url == "https://archive.org/details/manualgreeklexic00abborich/page/3/mode/1up"
      assert c.locator == "s.v. ἀγάπη, p. 3"
      assert c.book.year == 1922

      # Page 1, which the scan didn't number, by its leaf index.
      assert Citations.abbott_smith("G1", "α").url =~ "/page/n20/"

      # An entry the core pack keys by lemma (no Strong's number).
      assert Citations.abbott_smith("AS_ἀγγέλλω", "ἀγγέλλω").url =~ "/page/4/"
      refute Citations.strongs?("AS_ἀγγέλλω")
      assert Citations.strongs?("H7307G")

      # STEPBible's extended numbers have no Bible Hub page: STEP's instead.
      assert Citations.strongs("G20006").url == "https://www.stepbible.org/?q=strong=G20006"
    end
  end

  describe "cross references, notes, dictionary" do
    test "OpenBible cross references by English reference" do
      assert Citations.tsk("Jhn.3.16").url ==
               "https://www.openbible.info/labs/cross-references/search?q=John+3%3A16"

      assert Citations.tsk("Deu.32.8").url ==
               "https://www.openbible.info/labs/cross-references/search?q=Deuteronomy+32%3A8"
    end

    test "a Tyndale note reads on STEP (TNotes), its dataset at Aquifer's anchor" do
      c = Citations.tyndale_note(19_106, "John 3:16", "43003016")
      assert c.url == "https://www.stepbible.org/?q=version=TNotes@reference=Jhn.3.16"

      assert c.dataset_url ==
               "https://github.com/BibleAquifer/AquiferOpenStudyNotes/blob/bbb3f860/eng/md/43.content.md#john-316-id-19106"
    end

    test "a ranged note's anchor drops the dash as GitHub does" do
      c = Citations.tyndale_note(18_784, "John 1:1–18", 43_001_001)
      assert c.dataset_url =~ "#john-1118-id-18784"
    end

    test "unfoldingWord notes by book at Door43" do
      assert Citations.uw_note(210_981, "John 3:16 (#7)", "Jhn").url ==
               "https://git.door43.org/unfoldingWord/en_tn/src/branch/master/tn_JHN.tsv"
    end

    test "dictionary articles: the file is the initial, past a leading 'The'" do
      assert Citations.dictionary(3263, "Aaron").url ==
               "https://github.com/BibleAquifer/AquiferOpenBibleDictionary/blob/4d92a9ac/eng/md/001.content.md#aaron-id-3263"

      assert Citations.dictionary(3937, "Baal (Idol)").url =~ "/002.content.md#baal-idol-id-3937"
      assert Citations.dictionary(5280, "The Flood").url =~ "/006.content.md#the-flood-id-5280"
      assert Citations.dictionary(9108, "Zaanaim").url =~ "/026.content.md#"
    end

    test "key terms: 24 files, no U or X" do
      assert Citations.key_term("eng-t167-v1", "abba").url ==
               "https://github.com/BibleAquifer/FIAKeyTerms/blob/91e4a774/eng/md/001.content.md#abba-id-eng-t167-v1"

      assert Citations.key_term("eng-t142-v1", "vineyard").url =~ "/021.content.md#"
      assert Citations.key_term("eng-t286-v1", "zeal").url =~ "/024.content.md#"
    end
  end

  describe "people, places, events, Torah Weave" do
    test "ACAI pages by type directory and the id's name" do
      assert Citations.acai("person:Aaron").url ==
               "https://github.com/BibleAquifer/ACAI/blob/7e6a2d66/people/md/Aaron.md"

      assert Citations.acai("place:Cistern of sirah").url ==
               "https://github.com/BibleAquifer/ACAI/blob/7e6a2d66/places/md/Cistern%20of%20sirah.md"
    end

    test "Theographic people, places and slugged events" do
      assert Citations.person("aaron_1").url == "https://theographic.netlify.app/person/aaron_1/"

      assert Citations.place("bethel_202").url ==
               "https://theographic.netlify.app/place/bethel_202/"

      assert Citations.event(71, "Abraham enters Canaan").url ==
               "https://theographic.netlify.app/event/abraham_enters_canaan_71/"

      assert Citations.event("152", "Death of Eli, Ark Captured").url ==
               "https://theographic.netlify.app/event/death_of_eli_ark_captured_152/"

      assert Citations.event("87", "Nimrod's kingdom begins").url ==
               "https://theographic.netlify.app/event/nimrod_s_kingdom_begins_87/"
    end

    test "Torah Weave units at chaver.com" do
      assert Citations.torah_weave("Genesis", 1, "Creation").url ==
               "https://chaver.com/torah-weave/Genesis/genesis-unit-1/genesis-unit-1"
    end
  end

  describe "ancient sources" do
    test "Josephus at the Perseus Hopper, Whiston's English by book and section" do
      c = Citations.ancient("antiquities", "Antiquities 18.63–64")

      assert c.url ==
               "https://www.perseus.tufts.edu/hopper/text?doc=Perseus:text:1999.01.0146:book=18:section=63"

      assert Citations.ancient("life", "Life 101").url ==
               "https://www.perseus.tufts.edu/hopper/text?doc=Perseus:text:1999.01.0150:section=101"
    end

    test "Josephus's Greek when the tool gave no English" do
      c = Citations.ancient("jewish_war", "War 1.103–106", english: false)
      assert c.url =~ "Perseus:text:1999.01.0147:book=1:section=103"
      assert c.translation == :assistant
    end

    test "Philo at Scaife, by the dataset's TLG work number" do
      url =
        "https://github.com/OpenGreekAndLatin/First1KGreek/tree/03776b39/data/tlg0018/tlg001"

      c = Citations.ancient("opif", "Opif. 1", source_url: url)

      assert c.url ==
               "https://scaife.perseus.org/reader/urn:cts:greekLit:tlg0018.tlg001.1st1K-eng1:1/"

      assert c.dataset_url == url

      greek =
        Citations.ancient("spec", "Spec. 1.177",
          source_url: String.replace(url, "tlg001", "tlg024"),
          english: false
        )

      assert greek.url ==
               "https://scaife.perseus.org/reader/urn:cts:greekLit:tlg0018.tlg024.1st1K-grc1:1.177/"

      assert greek.translation == :assistant
    end

    test "Onkelos and the Mishnah at Sefaria; Onkelos's English isn't of the Aramaic" do
      onkelos = Citations.ancient("onkelos_genesis", "Targum Onkelos Genesis 1:1")
      assert onkelos.url == "https://www.sefaria.org/Onkelos_Genesis.1.1"
      assert onkelos.translation == :assistant

      assert Citations.ancient("mishnah_avodah_zarah", "Mishnah Avodah Zarah 1:1–2").url ==
               "https://www.sefaria.org/Mishnah_Avodah_Zarah.1.1"
    end

    test "1 Enoch's stored Wikisource page; 4 Ezra as 2 Esdras at eBible" do
      page =
        "https://en.wikisource.org/w/index.php?title=The_Book_of_Enoch_(Charles)/Chapter_01&oldid=13274564"

      assert Citations.ancient("1_enoch", "1 Enoch 1:1", source_url: page).url == page

      assert Citations.ancient("4_ezra", "4 Ezra 10:1").url ==
               "https://ebible.org/eng-kjv/2ES10.htm#V1"
    end

    test "the ancient pack's scrolls: Israel Museum, Cambridge, Leon Levy" do
      assert Citations.ancient("community_rule", "1QS 10:1–26").url ==
               "http://dss.collections.imj.org.il/community"

      assert Citations.ancient("pesher_habakkuk", "1QpHab 10:1–17").url ==
               "http://dss.collections.imj.org.il/habakkuk"

      assert Citations.ancient("damascus_document", "CD 10:1–23").url ==
               "https://cudl.lib.cam.ac.uk/view/MS-TS-00010-K-00006"

      assert Citations.ancient("damascus_document", "CD 20:1–34").url ==
               "https://cudl.lib.cam.ac.uk/view/MS-TS-00016-00311"

      assert Citations.ancient("rule_of_the_congregation", "1QSa 1:1–29").url ==
               "https://www.deadseascrolls.org.il/explore-the-archive/manuscript/1Q28a-1"
    end

    test "the scrolls pack's manuscripts, labelled by passage, the original only" do
      c = Citations.ancient("dss_4q266", "4Q266 frg. 1a–b 1–25")
      assert c.url == "https://www.deadseascrolls.org.il/explore-the-archive/manuscript/4Q266-1"
      assert c.label == "4Q266 frg. 1a–b 1–25"
      assert c.translation == :assistant
      assert c.licence == "CC BY-NC 4.0"

      assert Citations.ancient("dss_1qm", "1QM 1:1–20").url ==
               "http://dss.collections.imj.org.il/war"

      assert Citations.ancient("dss_11q19", "11Q19 2:1–15").url ==
               "http://dss.collections.imj.org.il/temple"

      hodayot = Citations.ancient("dss_1qha", "1QHa 2:12–32")
      assert hodayot.url == nil
      assert hodayot.book.title =~ "1QHodayot"
    end

    test "biblical manuscripts: Leon Levy only for the sigla it has a page for" do
      assert Citations.dss_manuscript("4Q37", "4Q37 12:13–14").url ==
               "https://www.deadseascrolls.org.il/explore-the-archive/manuscript/4Q37-1"

      assert Citations.dss_manuscript("1Qisaa").url == "http://dss.collections.imj.org.il/isaiah"
      # Leon Levy's Mur88-1 is a 404 and its 4Q51-1 another manuscript: an
      # unnamed siglum links the transcription it was read from.
      assert Citations.dss_manuscript("Mur88", nil, leon_levy: false).url ==
               "https://github.com/ETCBC/dss"
    end
  end

  describe "scholarship" do
    test "a theology entry with a URL keeps it and its pages" do
      c =
        Citations.theology(%{
          source_author: "heiser",
          source_work: "Heiser — Deuteronomy 32:8 and the Sons of God (BibSac paper)",
          chapter_or_episode: "The LXX and DSS readings",
          page_range: "pp. 52-55",
          url: "https://www.thedivinecouncil.com/DT32BibSac.pdf"
        })

      assert c.url == "https://www.thedivinecouncil.com/DT32BibSac.pdf"
      assert c.locator == "pp. 52-55"
      assert c.work == "theology:heiser"
    end

    test "a theology entry with no URL is its book: author, title, year" do
      c =
        Citations.theology(%{
          source_author: "stott",
          source_work: "Stott on Romans",
          chapter_or_episode: "Romans 1:16-17 (The theme of the letter)"
        })

      assert c.url == nil

      assert Citation.link(c) ==
               "John Stott, *The Message of Romans* (1994), on Romans 1:16-17 (The theme of the letter)"
    end

    test "the HLT is an unpublished draft with its originals, never Heiser's" do
      witness = Citations.dss_manuscript("4Q37", "4Q37 12:13–14")
      c = Citations.hlt("Deu.32.8", [witness])
      assert c.translation == :unpublished_draft
      assert Enum.map(c.original, & &1.label) == ["Hebrew (MT)", "Greek (LXX)", "4Q37 12:13–14"]

      line = Citation.source_line(c)
      assert line =~ "not Heiser's"
      assert line =~ "[Hebrew (MT)](https://www.stepbible.org/?q=version=THOT@reference=Deu.32.8)"
    end

    test "Fee and Stuart is a book" do
      assert Citation.link(Citations.fee_stuart("the Gospels")) ==
               "Gordon D. Fee and Douglas Stuart, *How to Read the Bible for All Its Worth* (1982), on the Gospels"
    end
  end

  describe "lists" do
    test "mark: cited when the reply links its URL (as written or encoded), or names its book" do
      net = Citations.net("Jhn.3.16")
      lsj = Citations.lsj("G0026", "ἀγάπη")
      book = Citations.fee_stuart()
      other = Citations.net("Jhn.3.17")
      # John 3:1's URL is the start of John 3:16's: not cited by it.
      prefix = Citations.net("Jhn.3.1")

      text =
        "God loved the world ([NET](https://netbible.org/bible/John+3:16)); " <>
          "LSJ ([ἀγάπη](https://lsj.gr/wiki/ἀγάπη)); see How to Read the Bible for All Its Worth."

      assert [true, true, true, false, false] ==
               [net, lsj, book, other, prefix] |> Citations.mark(text) |> Enum.map(& &1.cited)
    end

    test "dedupe by URL and place, by_work in order of first use" do
      a = Citations.net("Jhn.3.16")
      b = Citations.bdb("H430")
      c = Citations.net("Jhn.3.17")

      assert Citations.dedupe([a, b, a, c]) == [a, b, c]

      # Two passages of 1QS share the Israel Museum's page but stay two.
      one = Citations.ancient("community_rule", "1QS 1:1–26")
      three = Citations.ancient("community_rule", "1QS 3:1–26")
      assert one.url == three.url
      assert Citations.dedupe([one, three, one]) == [one, three]

      assert [{"net", "NET Bible", [^a, ^c]}, {"bdb", "Brown-Driver-Briggs", [^b]}] =
               Citations.by_work([a, b, c])
    end

    test "a citation survives the session's JSON" do
      c = Citations.hlt("Deu.32.8")
      stored = c |> Citation.to_map() |> Jason.encode!() |> Jason.decode!()
      assert Citation.from_map(stored) == c

      book = Citations.fee_stuart("Epistles")

      back =
        book |> Citation.to_map() |> Jason.encode!() |> Jason.decode!() |> Citation.from_map()

      assert Citation.link(back) == Citation.link(book)
    end

    test "source lines for the model" do
      assert Citation.source_line(Citations.net("Jhn.3.16")) ==
               "Source: [John 3:16](https://netbible.org/bible/John+3:16)"

      assert Citation.source_line(Citations.dss_manuscript("4Q37", "4Q37 12:13–14")) =~
               "any English you give for it is your own translation"

      assert Citation.source_line([]) == ""
    end
  end
end
