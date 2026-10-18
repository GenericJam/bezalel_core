defmodule Bezalel.Study.Citations do
  @moduledoc """
  Every URL Bezalel cites a source with: one function per work, each
  returning a `Bezalel.Study.Citation` for one record (a verse, a lexicon
  entry, a note, an ancient passage, a manuscript, a book). The study tools
  call these and nothing else builds a source URL, so a site that moves is
  fixed here once.

  The templates were checked against the live sites on 2026-10-18 (the
  decision record `decisions/2026-10-18-sources.md` lists them); the tests
  pin each to a verified example. Pack references go in as the packs store
  them ('Jhn.3.16', 'Psa.3.0'); English book names come from
  `Bezalel.Study.Reference.book_name/1`, and a pack's book code upper-cased
  is the USFM code eBible and Door43 use.

  Also here: `mark/2` (which citations a reply links), `dedupe/1`,
  `by_work/1` (a sources list's groups) and `work_title/1`.
  """

  alias Bezalel.Study.{Citation, Patterns, Reference}

  # The 66 books in the order Aquifer numbers them (01 Genesis … 66 Revelation).
  @canon ~w(Gen Exo Lev Num Deu Jos Jdg Rut 1Sa 2Sa 1Ki 2Ki 1Ch 2Ch Ezr Neh Est Job Psa Pro
            Ecc Sng Isa Jer Lam Ezk Dan Hos Jol Amo Oba Jon Mic Nam Hab Zep Hag Zec Mal Mat Mrk
            Luk Jhn Act Rom 1Co 2Co Gal Eph Php Col 1Th 2Th 1Ti 2Ti Tit Phm Heb Jas 1Pe 2Pe 1Jn
            2Jn 3Jn Jud Rev)
  @nt MapSet.new(Enum.drop(@canon, 39))

  # Pinned commits of the datasets imported from GitHub.
  @aquifer %{
    study_notes: {"AquiferOpenStudyNotes", "bbb3f860"},
    dictionary: {"AquiferOpenBibleDictionary", "4d92a9ac"},
    key_terms: {"FIAKeyTerms", "91e4a774"},
    uw: {"UWTranslationNotes", "dbfb46e0"},
    sil: {"SILOpenTranslatorsNotes", "0ba58c29"}
  }
  @acai_commit "7e6a2d66"

  # FIA Key Terms' 24 Markdown files, one per initial (no U or X).
  @key_term_letters ~c"ABCDEFGHIJKLMNOPQRSTVWYZ"

  @acai_dirs %{
    "person" => "people",
    "place" => "places",
    "group" => "groups",
    "keyterm" => "keyterms",
    "deity" => "deities",
    "fauna" => "fauna",
    "flora" => "flora",
    "realia" => "realia"
  }

  # Rahlfs book codes whose Brenton file on eBible has another name.
  @brenton_books %{"Dan" => "DAG", "EsG" => "ESG", "Lje" => "LJE"}

  # Josephus at the Perseus Hopper: {English (Whiston) doc, Greek (Niese) doc}.
  @josephus %{
    "antiquities" => {"1999.01.0146", "1999.01.0145", "Antiquities"},
    "jewish_war" => {"1999.01.0148", "1999.01.0147", "War"},
    "against_apion" => {"1999.01.0216", "1999.01.0215", "Against Apion"},
    "life" => {"1999.01.0150", "1999.01.0149", "Life"}
  }

  # The ancient pack's Qumran works, by work key: their manuscript siglum.
  @qumran_works %{
    "community_rule" => "1QS",
    "damascus_document" => "CD",
    "pesher_habakkuk" => "1QpHab",
    "rule_of_the_congregation" => "1QSa"
  }

  @imj "http://dss.collections.imj.org.il/"
  @leon_levy "https://www.deadseascrolls.org.il/explore-the-archive/manuscript/"
  # Scrolls with no Leon Levy page of their own: the Israel Museum's, and
  # the Cairo Genizah copies of the Damascus Document at Cambridge.
  @scroll_pages %{
    "1QIsaa" => @imj <> "isaiah",
    "1QS" => @imj <> "community",
    "1QpHab" => @imj <> "habakkuk",
    "1QM" => @imj <> "war",
    "11Q19" => @imj <> "temple"
  }
  # Leon Levy files the two 1QS appendices under their cave numbers.
  @leon_levy_sigla %{"1QSa" => "1Q28a", "1QSb" => "1Q28b"}
  @cd_a "https://cudl.lib.cam.ac.uk/view/MS-TS-00010-K-00006"
  @cd_b "https://cudl.lib.cam.ac.uk/view/MS-TS-00016-00311"
  @etcbc_dss "https://github.com/ETCBC/dss"
  @hodayot %{
    author: "Hartmut Stegemann with Eileen Schuller",
    title: "Qumran Cave 1.III: 1QHodayot a (DJD 40)",
    year: 2009
  }

  # The books studybible-mcp summarises, by its `source_work`: author,
  # title and year of first publication (no edition: the data records none).
  @books %{
    "Stott on Romans" => %{author: "John Stott", title: "The Message of Romans", year: 1994},
    "Stott on Galatians" => %{author: "John Stott", title: "The Message of Galatians", year: 1968},
    "Stott on Ephesians" => %{author: "John Stott", title: "The Message of Ephesians", year: 1979},
    "Stott on Acts and the work of the Spirit" => %{
      author: "John Stott",
      title: "The Message of Acts",
      year: 1990
    },
    "Stott on the Sermon on the Mount" => %{
      author: "John Stott",
      title: "The Message of the Sermon on the Mount",
      year: 1978
    },
    "Stott on the cross and the atonement" => %{
      author: "John Stott",
      title: "The Cross of Christ",
      year: 1986
    },
    "Stott on the person and claims of Christ" => %{
      author: "John Stott",
      title: "Basic Christianity",
      year: 1958
    },
    "Lennox on Daniel — faithful witness under empire" => %{
      author: "John C. Lennox",
      title: "Against the Flow: The Inspiration of Daniel in an Age of Relativism",
      year: 2015
    },
    "Lennox on Genesis 1 — creation and science" => %{
      author: "John C. Lennox",
      title: "Seven Days That Divide the World",
      year: 2011
    },
    "Lennox on Joseph — providence and the problem of evil" => %{
      author: "John C. Lennox",
      title: "Joseph: A Story of Love, Hate, Slavery, Power, and Forgiveness",
      year: 2019
    },
    "Bradley — Two Fathers Only (paper)" => %{
      author: "Bradley",
      title: "Two Fathers Only: Rival Pater Familias and the Organizing Binary of Scripture",
      year: nil
    }
  }

  @fee_stuart %{
    author: "Gordon D. Fee and Douglas Stuart",
    title: "How to Read the Bible for All Its Worth",
    year: 1982
  }

  @abbott_smith_item "https://archive.org/details/manualgreeklexic00abborich"
  @abbott_smith_book %{
    author: "G. Abbott-Smith",
    title: "A Manual Greek Lexicon of the New Testament",
    year: 1922
  }

  # Read at compile time (mix links priv into the build before compiling), so
  # the device needs no priv file. Built by data/'s `mix bezalel.data.abbott_smith`.
  @abbott_smith_path Application.app_dir(:bezalel_core, "priv/study/abbott_smith_pages.json")
  @external_resource @abbott_smith_path
  @abbott_smith_json @abbott_smith_path |> File.read!() |> JSON.decode!()
  @abbott_smith_pages @abbott_smith_json["pages"]
  @abbott_smith_tokens @abbott_smith_json["scan_tokens"]

  @studybible "https://github.com/djayatillake/studybible-mcp"
  @step_data "https://github.com/STEPBible/STEPBible-Data"
  @by_nc "CC BY-NC 4.0"

  @titles %{
    "net" => "NET Bible",
    "bsb" => "Berean Standard Bible",
    "step" => "STEP Bible",
    "lxx" => "Septuagint (Rahlfs)",
    "brenton" => "Brenton's Septuagint",
    "bdb" => "Brown-Driver-Briggs",
    "lsj" => "LSJ",
    "abbott_smith" => "Abbott-Smith",
    "strongs" => "Strong's numbers (Bible Hub)",
    "tsk" => "OpenBible.info cross references",
    "tyndale_notes" => "Tyndale Open Study Notes",
    "tyndale_dictionary" => "Tyndale Open Bible Dictionary",
    "uw_notes" => "unfoldingWord Translation Notes",
    "sil_notes" => "SIL Open Translator's Notes",
    "fia" => "FIA Key Terms",
    "acai" => "ACAI",
    "theographic" => "Theographic",
    "torah_weave" => "Torah Weave",
    "josephus" => "Josephus",
    "philo" => "Philo",
    "onkelos" => "Targum Onkelos",
    "mishnah" => "Mishnah",
    "enoch" => "1 Enoch",
    "4ezra" => "4 Ezra",
    "dss" => "Dead Sea Scrolls",
    "ane" => "ANE context",
    "textual" => "Textual variants",
    "hlt" => "Unpublished draft renderings",
    "fee_stuart" => "Fee & Stuart",
    "research" => "Research sources",
    "studybible" => "studybible-mcp"
  }

  # ── Scripture ────────────────────────────────────────────────────────────

  @typedoc "A verse: the packs' reference ('Jhn.3.16') or `{book code, chapter, verse}`."
  @type verse :: String.t() | {String.t(), non_neg_integer(), non_neg_integer()}

  @doc """
  A verse of the NET Bible at netbible.org (its terms: "NET" linked to the
  site; a verse page satisfies them). A Psalm superscription (verse 0) is
  its chapter's first verse.
  """
  @spec net(verse()) :: Citation.t()
  def net(verse) do
    {book, chapter, v} = parse(verse)
    name = Reference.book_name(book)

    %Citation{
      work: "net",
      label: place(name, chapter, v),
      locator: place(name, chapter, v),
      url: "https://netbible.org/bible/#{String.replace(name, " ", "+")}+#{chapter}:#{max(v, 1)}"
    }
  end

  @doc "A verse of the Berean Standard Bible at Bible Hub (a BSB co-producer)."
  @spec bsb(verse()) :: Citation.t()
  def bsb(verse) do
    {book, chapter, v} = parse(verse)
    name = Reference.book_name(book)

    %Citation{
      work: "bsb",
      label: place(name, chapter, v),
      locator: place(name, chapter, v),
      url: "https://biblehub.com/#{biblehub_slug(book, name)}/#{chapter}-#{max(v, 1)}.htm"
    }
  end

  @doc """
  A verse quoted in `translation` (a `Bezalel.Study.Translations` key or
  map): `net/1` or `bsb/1`; a verse with only STEPBible's gloss (`nil`) is
  its original on STEP (`step/1`).
  """
  @spec scripture(verse(), String.t() | map() | nil) :: Citation.t()
  def scripture(verse, %{key: key}), do: scripture(verse, key)
  def scripture(verse, "net"), do: net(verse)
  def scripture(verse, "bsb"), do: bsb(verse)
  def scripture(verse, _none), do: step(verse)

  @doc """
  A verse's Hebrew (THOT) or Greek (THGNT) on STEP Bible, the text and
  word data the packs carry (STEPBible's TAHOT/TAGNT).
  """
  @spec step(verse()) :: Citation.t()
  def step(verse) do
    {book, chapter, v} = parse(verse)

    {version, language} =
      if MapSet.member?(@nt, book), do: {"THGNT", "Greek"}, else: {"THOT", "Hebrew"}

    %Citation{
      work: "step",
      label: "#{place(Reference.book_name(book) || book, chapter, v)} (#{language})",
      locator: "#{book}.#{chapter}.#{v}",
      url: step_url(version, book, chapter, v)
    }
  end

  @doc """
  A verse of the Septuagint (Rahlfs) on STEP Bible, by its English
  (canonical) reference: STEP maps it to the Greek numbering. `english:
  false` when the tool gave no English for it (no Brenton): any English is
  the assistant's.
  """
  @spec lxx(verse(), keyword()) :: Citation.t()
  def lxx(verse, opts \\ []) do
    {book, chapter, v} = parse(verse)
    url = step_url("LXX", book, chapter, v)
    label = "#{place(Reference.book_name(book) || book, chapter, v)} (LXX)"

    %Citation{work: "lxx", label: label, locator: "#{book}.#{chapter}.#{v}", url: url}
    |> translated(Keyword.get(opts, :english, true))
  end

  @doc """
  A verse of Brenton's *Septuagint with Apocrypha* (1851) at eBible.org, by
  its Rahlfs (edition) reference: Psalms in Greek numbering, Rahlfs's 2
  Esdras split back into Ezra and Nehemiah.
  """
  @spec brenton(verse()) :: Citation.t()
  def brenton(verse) do
    {book, chapter, v} = parse(verse)

    {file, file_chapter} =
      case book do
        "2Es" when chapter > 10 -> {"NEH", chapter - 10}
        "2Es" -> {"EZR", chapter}
        _ -> {Map.get(@brenton_books, book, String.upcase(book)), chapter}
      end

    digits = if file == "PSA", do: 3, else: 2
    number = file_chapter |> Integer.to_string() |> String.pad_leading(digits, "0")

    %Citation{
      work: "brenton",
      label: "#{place(Reference.book_name(book) || book, chapter, v)} (Brenton)",
      locator: "#{book}.#{chapter}.#{v}",
      url: "https://ebible.org/eng-Brenton/#{file}#{number}.htm#V#{v}"
    }
  end

  # "John 3:16"; a Psalm's superscription (verse 0) as "Psalms 22 (superscription)".
  defp place(name, chapter, 0), do: "#{name} #{chapter} (superscription)"
  defp place(name, chapter, verse), do: "#{name} #{chapter}:#{verse}"

  # ── Lexicons ─────────────────────────────────────────────────────────────

  @doc """
  A Hebrew entry of Brown-Driver-Briggs, at Bible Hub (the same BDB text);
  STEPBible's entry for an extended number (H9000…), which Bible Hub lacks.
  """
  @spec bdb(String.t(), String.t() | nil) :: Citation.t()
  def bdb(strongs, word \\ nil) do
    {"H", n} = strongs_number(strongs)

    %Citation{
      work: "bdb",
      label: Enum.join(Enum.reject(["BDB H#{n}", word], &blank?/1), " "),
      locator: "H#{n}",
      url:
        if(classic?("H", n),
          do: "https://biblehub.com/bdb/#{n}.htm",
          else: "https://www.stepbible.org/?q=strong=H#{n}"
        )
    }
  end

  @doc """
  A Greek entry of LSJ (STEPBible's formatted LSJ in the packs), at lsj.gr
  by its lemma: the first, when the pack lists several ('ἄρρην, ἄρσην');
  STEPBible's entry when it has none.
  """
  @spec lsj(String.t(), String.t()) :: Citation.t()
  def lsj(strongs, lemma) do
    {"G", n} = strongs_number(strongs)

    case lemma |> to_string() |> String.split([",", ";", " "], trim: true) do
      [first | _] ->
        %Citation{
          work: "lsj",
          label: "LSJ #{first}",
          locator: "G#{n}",
          url: "https://lsj.gr/wiki/" <> URI.encode(first, &URI.char_unreserved?/1)
        }

      [] ->
        %Citation{
          work: "lsj",
          label: "LSJ G#{n}",
          locator: "G#{n}",
          url: "https://www.stepbible.org/?q=strong=G#{n}"
        }
    end
  end

  @doc """
  Whether `key` is a Strong's number ('H430', 'G0026', 'H7307G'), which
  the Strong's-keyed lexicon citations take; the core pack keys an
  Abbott-Smith entry with none as `"AS_<lemma>"`.
  """
  @spec strongs?(term()) :: boolean()
  def strongs?(key) when is_binary(key),
    do: Regex.match?(Patterns.get(:citation_strongs), String.upcase(String.trim(key)))

  def strongs?(_key), do: false

  @doc """
  A Greek entry of Abbott-Smith's *Manual Greek Lexicon* (1922): the scan
  at the Internet Archive, at the entry's page when
  `priv/study/abbott_smith_pages.json` knows it, with the book reference.
  `key` is the entry's Strong's number, or the core pack's `"AS_<lemma>"`
  for an Abbott-Smith entry with none.
  """
  @spec abbott_smith(String.t(), String.t()) :: Citation.t()
  def abbott_smith(key, lemma) do
    page_key =
      case key do
        "AS_" <> _ -> key
        strongs -> "G#{elem(strongs_number(strongs), 1)}"
      end

    {locator, url} =
      case abbott_smith_page(page_key) do
        {page, token} ->
          {"s.v. #{lemma}, p. #{page}", "#{@abbott_smith_item}/page/#{token}/mode/1up"}

        nil ->
          {"s.v. #{lemma}", @abbott_smith_item}
      end

    %Citation{
      work: "abbott_smith",
      label: "Abbott-Smith, #{locator}",
      locator: locator,
      url: url,
      book: @abbott_smith_book
    }
  end

  @doc "A Strong's number's page at Bible Hub."
  @spec strongs(String.t(), String.t() | nil) :: Citation.t()
  def strongs(strongs, word \\ nil) do
    {letter, n} = strongs_number(strongs)
    language = if letter == "H", do: "hebrew", else: "greek"

    %Citation{
      work: "strongs",
      label: Enum.join(Enum.reject(["Strong's #{letter}#{n}", word], &blank?/1), " "),
      locator: "#{letter}#{n}",
      url:
        if(classic?(letter, n),
          do: "https://biblehub.com/#{language}/#{n}.htm",
          else: "https://www.stepbible.org/?q=strong=#{letter}#{n}"
        )
    }
  end

  # Strong's own numbers (H1–H8674, G1–G5624), which Bible Hub has pages
  # for; STEPBible's extended ones (G20006) are on STEP only.
  defp classic?("H", n), do: n <= 8674
  defp classic?("G", n), do: n <= 5624

  @doc "A word's entry in STEPBible's brief lexicons (TBESH, TBESG) on STEP Bible."
  @spec step_lexicon(String.t(), String.t() | nil) :: Citation.t()
  def step_lexicon(strongs, word \\ nil) do
    {letter, n} = strongs_number(strongs)
    padded = letter <> String.pad_leading(Integer.to_string(n), 4, "0")

    %Citation{
      work: "step",
      label: Enum.join(Enum.reject(["STEP lexicon #{padded}", word], &blank?/1), " "),
      locator: padded,
      url: "https://www.stepbible.org/?q=strong=#{padded}"
    }
  end

  @doc "STEPBible's morphology codes (TEHMC, TEGMC): the dataset; no page per code."
  @spec morphology(String.t()) :: Citation.t()
  def morphology(code) do
    %Citation{
      work: "step",
      label: "STEPBible morphology codes (#{code})",
      locator: code,
      url: @step_data
    }
  end

  @doc "STEPBible's proper names (TIPNR): the dataset; no page per name."
  @spec proper_name(String.t()) :: Citation.t()
  def proper_name(name) do
    %Citation{
      work: "step",
      label: "STEPBible proper names (#{name})",
      locator: name,
      url: @step_data
    }
  end

  # ── Cross references ─────────────────────────────────────────────────────

  @doc "A verse's cross references at OpenBible.info (the Treasury of Scripture Knowledge, with votes)."
  @spec tsk(verse()) :: Citation.t()
  def tsk(verse) do
    {book, chapter, v} = parse(verse)
    name = Reference.book_name(book)

    %Citation{
      work: "tsk",
      label: "#{name} #{chapter}:#{v} cross references",
      locator: "#{name} #{chapter}:#{v}",
      url:
        "https://www.openbible.info/labs/cross-references/search?q=" <>
          "#{String.replace(name, " ", "+")}+#{chapter}%3A#{v}"
    }
  end

  @doc "studybible-mcp's own material (thematic chains, synthesis notes): its repository."
  @spec studybible(String.t()) :: Citation.t()
  def studybible(label), do: %Citation{work: "studybible", label: label, url: @studybible}

  # ── Notes, dictionary, key terms ─────────────────────────────────────────

  @doc """
  A Tyndale Open Study Note (via Aquifer): read on STEP Bible (TNotes, the
  same notes) at its first verse; `start_ref` is Aquifer's BBCCCVVV.
  """
  @spec tyndale_note(String.t() | integer(), String.t(), String.t() | integer()) :: Citation.t()
  def tyndale_note(content_id, title, start_ref) do
    ref = start_ref |> to_string() |> String.pad_leading(8, "0")
    {number, chapter, v} = bbcccvvv(ref)
    book = Enum.at(@canon, number - 1)

    %Citation{
      work: "tyndale_notes",
      label: "#{title} (Tyndale note)",
      locator: title,
      url: step_url("TNotes", book, chapter, v),
      dataset_url:
        aquifer_url(:study_notes, String.pad_leading("#{number}", 2, "0"), title, content_id)
    }
  end

  @doc "An unfoldingWord Translation Note: its book's notes at Door43 (no verse anchors there)."
  @spec uw_note(String.t() | integer(), String.t(), String.t()) :: Citation.t()
  def uw_note(content_id, title, book) do
    {repo, commit} = @aquifer.uw

    %Citation{
      work: "uw_notes",
      label: "#{title} (unfoldingWord note)",
      locator: title,
      url:
        "https://git.door43.org/unfoldingWord/en_tn/src/branch/master/tn_#{String.upcase(book)}.tsv",
      dataset_url: "https://github.com/BibleAquifer/#{repo}/tree/#{commit}##{content_id}"
    }
  end

  @doc "An SIL Open Translator's Note: opentn.bible has no page per note, so its site."
  @spec sil_note(String.t() | integer(), String.t()) :: Citation.t()
  def sil_note(content_id, title) do
    {repo, commit} = @aquifer.sil

    %Citation{
      work: "sil_notes",
      label: "#{title} (SIL note)",
      locator: title,
      url: "https://opentn.bible/",
      dataset_url: "https://github.com/BibleAquifer/#{repo}/tree/#{commit}##{content_id}"
    }
  end

  @doc """
  A Tyndale Open Bible Dictionary article (via Aquifer): its heading in
  Aquifer's Markdown, one file per initial ("The Flood" under F).
  """
  @spec dictionary(String.t() | integer(), String.t()) :: Citation.t()
  def dictionary(content_id, title) do
    file = (initial(title) - ?A + 1) |> Integer.to_string() |> String.pad_leading(3, "0")

    %Citation{
      work: "tyndale_dictionary",
      label: "#{title} (Tyndale Bible Dictionary)",
      locator: title,
      url: aquifer_url(:dictionary, file, title, content_id)
    }
  end

  @doc "An FIA Key Terms article (via Aquifer): its heading in Aquifer's Markdown, one file per initial."
  @spec key_term(String.t(), String.t()) :: Citation.t()
  def key_term(content_id, title) do
    index = Enum.find_index(@key_term_letters, &(&1 == initial(title))) || 0
    file = (index + 1) |> Integer.to_string() |> String.pad_leading(3, "0")

    %Citation{
      work: "fia",
      label: "#{title} (FIA Key Terms)",
      locator: title,
      url: aquifer_url(:key_terms, file, title, content_id)
    }
  end

  # ── People, places, events ───────────────────────────────────────────────

  @doc "An ACAI entity ('person:Aaron'): its Markdown page in ACAI's repository."
  @spec acai(String.t(), String.t() | nil) :: Citation.t()
  def acai(id, name \\ nil) do
    [type, file] = String.split(id, ":", parts: 2)
    dir = Map.get(@acai_dirs, type, type)

    %Citation{
      work: "acai",
      label: "#{name || file} (ACAI)",
      locator: id,
      url:
        "https://github.com/BibleAquifer/ACAI/blob/#{@acai_commit}/#{dir}/md/" <>
          URI.encode(file <> ".md", &URI.char_unreserved?/1)
    }
  end

  @doc "A person in Theographic ('aaron_1')."
  @spec person(String.t(), String.t() | nil) :: Citation.t()
  def person(id, name \\ nil), do: theographic("person", id, name)

  @doc "A place in Theographic ('bethel_202'), with Easton's article and OpenBible's coordinates."
  @spec place(String.t(), String.t() | nil) :: Citation.t()
  def place(id, name \\ nil), do: theographic("place", id, name)

  @doc "An event in Theographic: its page is its title slugged, then its id."
  @spec event(String.t() | integer(), String.t()) :: Citation.t()
  def event(id, title) do
    slug =
      Patterns.get(:slug_separator)
      |> Regex.replace(String.downcase(title), "_")
      |> String.trim("_")

    theographic("event", "#{slug}_#{id}", title)
  end

  defp theographic(kind, id, name) do
    %Citation{
      work: "theographic",
      label: "#{name || id} (Theographic)",
      locator: id,
      url: "https://theographic.netlify.app/#{kind}/#{id}/"
    }
  end

  @doc "A unit of Moshe Kline's Torah Weave at chaver.com."
  @spec torah_weave(String.t(), integer(), String.t() | nil) :: Citation.t()
  def torah_weave(book_full, unit, title \\ nil) do
    slug = "#{String.downcase(book_full)}-unit-#{unit}"

    %Citation{
      work: "torah_weave",
      label: Enum.join(Enum.reject(["#{book_full} unit #{unit}", title], &blank?/1), ": "),
      locator: "#{book_full} #{unit}",
      url: "https://chaver.com/torah-weave/#{book_full}/#{slug}/#{slug}"
    }
  end

  # ── Ancient sources ──────────────────────────────────────────────────────

  @doc """
  An ancient passage by its work key and reference as the packs store them
  ('antiquities', 'Antiquities 18.63–64'). Options: `:source_url` (the
  row's pinned dataset URL: Philo's work number and 1 Enoch's Wikisource
  page come from it), `:english` (false when the tool gave the original
  only: the citation is then `:assistant`), `:alternate_reference` (the
  row's other numbering: 4 Ezra's KJV 2 Esdras verse, which the KJV page
  is anchored by; 4 Ezra 7:106 is 2 Esdras 7:36).
  """
  @spec ancient(String.t(), String.t(), keyword()) :: Citation.t()
  def ancient(work_key, reference, opts \\ []) do
    english? = Keyword.get(opts, :english, true)
    source_url = opts[:source_url]

    work_key
    |> ancient_citation(reference, english?, source_url)
    |> Map.put(:dataset_url, source_url)
    |> kjv_anchor(work_key, opts[:alternate_reference])
  end

  defp kjv_anchor(citation, "4_ezra", "KJV " <> esdras) do
    case verse_of(esdras) do
      {"2 Esdras", chapter, verse} -> %{citation | url: esdras_url(chapter, verse)}
      _ -> citation
    end
  end

  defp kjv_anchor(citation, _work_key, _alternate), do: citation

  defp esdras_url(chapter, verse) do
    number = chapter |> Integer.to_string() |> String.pad_leading(2, "0")
    "https://ebible.org/eng-kjv/2ES#{number}.htm#V#{verse}"
  end

  defp ancient_citation(work_key, reference, english?, _source_url)
       when is_map_key(@josephus, work_key) do
    {english_doc, greek_doc, _name} = @josephus[work_key]
    doc = if english?, do: english_doc, else: greek_doc
    edition = if english?, do: "Whiston", else: "Niese"

    place =
      case String.split(first_locator(reference), ".") do
        [book, section] -> "book=#{book}:section=#{section}"
        [section] -> "section=#{section}"
      end

    %Citation{
      work: "josephus",
      label: "#{reference} (#{edition})",
      locator: reference,
      url: "https://www.perseus.tufts.edu/hopper/text?doc=Perseus:text:#{doc}:#{place}"
    }
    |> translated(english?)
  end

  defp ancient_citation("onkelos_" <> _ = _work_key, reference, _english?, _source_url) do
    # Metsudah's English translates the Hebrew Torah, not the Aramaic: any
    # English for the Targum itself is the assistant's.
    {book, chapter, verse} = verse_of(String.replace_prefix(reference, "Targum Onkelos ", ""))

    %Citation{
      work: "onkelos",
      label: reference,
      locator: reference,
      url: "https://www.sefaria.org/Onkelos_#{book}.#{chapter}.#{verse}",
      licence: @by_nc
    }
    |> translated(false)
  end

  defp ancient_citation("mishnah_" <> _, reference, english?, _source_url) do
    {tractate, chapter, mishnah} = verse_of(String.replace_prefix(reference, "Mishnah ", ""))
    # Sefaria files Avot as 'Pirkei_Avot', every other tractate as 'Mishnah_<Tractate>'.
    title =
      if tractate == "Pirkei Avot",
        do: "Pirkei_Avot",
        else: "Mishnah_" <> String.replace(tractate, " ", "_")

    %Citation{
      work: "mishnah",
      label: reference,
      locator: reference,
      url: "https://www.sefaria.org/#{title}.#{chapter}.#{mishnah}"
    }
    |> translated(english?)
  end

  defp ancient_citation("1_enoch", reference, english?, source_url) do
    %Citation{work: "enoch", label: "#{reference} (Charles)", locator: reference, url: source_url}
    |> translated(english?)
  end

  defp ancient_citation("4_ezra", reference, english?, _source_url) do
    {_, chapter, verse} = verse_of(reference)

    %Citation{
      work: "4ezra",
      label: "#{reference} (KJV 2 Esdras)",
      locator: reference,
      url: esdras_url(chapter, verse)
    }
    |> translated(english?)
  end

  defp ancient_citation(work_key, reference, _english?, _source_url)
       when is_map_key(@qumran_works, work_key) or binary_part(work_key, 0, 4) == "dss_" do
    siglum = Map.get(@qumran_works, work_key) || reference |> String.split(" ") |> hd()
    %{dss_manuscript(siglum, reference) | label: reference, locator: reference}
  end

  defp ancient_citation(work_key, reference, english?, source_url) do
    # Philo (and any work keyed like it): Scaife by the TLG work number in
    # the dataset path, cited by section or book.section.
    tlg = source_url |> to_string() |> String.split("/") |> List.last()

    if String.starts_with?(tlg, "tlg") do
      edition = if english?, do: "1st1K-eng1", else: "1st1K-grc1"
      section = first_locator(reference)

      %Citation{
        work: "philo",
        label: "#{reference} (#{if english?, do: "Yonge", else: "Cohn–Wendland"})",
        locator: reference,
        url:
          "https://scaife.perseus.org/reader/urn:cts:greekLit:tlg0018.#{tlg}.#{edition}:#{section}/"
      }
      |> translated(english?)
    else
      %Citation{work: work_key, label: reference, locator: reference, url: source_url}
      |> translated(english?)
    end
  end

  @doc """
  A Dead Sea Scroll manuscript, by its siglum ('4Q37', '1QS', 'CD'): its
  Leon Levy Digital Library page (plates, infrared images, the DJD
  edition), the Israel Museum's for its scrolls (1QIsaa, 1QS, 1QpHab, 1QM,
  11Q19), Cambridge's Genizah copies for CD (MS A, columns 1–16; MS B,
  19–20), and the DJD volume for 1QHa, which has no page. `locator` (the
  passage, '4Q37 12:13–14', 'CD 20:1') picks CD's copy. Options:
  `leon_levy: false` for a siglum Leon Levy has no page for (the biblical
  manuscripts with no name in the scrolls pack): those link the ETCBC/dss
  transcription the reading came from. The tools give the
  scrolls' Hebrew and Aramaic only, so any English is the assistant's.
  """
  @spec dss_manuscript(String.t(), String.t() | nil, keyword()) :: Citation.t()
  def dss_manuscript(siglum, locator \\ nil, opts \\ []) do
    base = %Citation{
      work: "dss",
      label: locator || siglum,
      locator: locator || siglum,
      licence: @by_nc
    }

    canonical = if String.downcase(siglum) == "1qisaa", do: "1QIsaa", else: siglum

    citation =
      cond do
        canonical == "CD" -> %{base | url: cd_copy(locator)}
        Map.has_key?(@scroll_pages, canonical) -> %{base | url: @scroll_pages[canonical]}
        canonical == "1QHa" -> %{base | book: @hodayot}
        Keyword.get(opts, :leon_levy, true) -> %{base | url: leon_levy(canonical)}
        # No page of its own anywhere we can trust (Leon Levy files unnamed
        # sigla under other manuscripts): the transcription it was read from.
        true -> %{base | url: @etcbc_dss}
      end

    translated(citation, false)
  end

  defp cd_copy(locator) do
    column = locator |> to_string() |> String.replace_prefix("CD ", "") |> first_locator()

    case Integer.parse(column) do
      {n, _} when n >= 19 -> @cd_b
      _ -> @cd_a
    end
  end

  defp leon_levy(siglum) do
    # A joined siglum ('4Q223–224') is filed under its first manuscript.
    [first | _] = String.split(Map.get(@leon_levy_sigla, siglum, siglum), ["–", "-"])
    @leon_levy <> URI.encode(first, &URI.char_unreserved?/1) <> "-1"
  end

  # ── Scholarship ──────────────────────────────────────────────────────────

  @doc """
  An entry of studybible-mcp's theology summaries (`get_theology_context`'s
  entry: `source_author`, `source_work`, `chapter_or_episode`,
  `page_range`, `url`): its stored URL and page range when it has one
  (Heiser, Owen), else the book it summarises (Stott, Lennox, Bradley),
  "on" the chapter it treats.
  """
  @spec theology(map()) :: Citation.t()
  def theology(entry) do
    author = entry[:source_author] || "studybible"
    work = entry[:source_work] || ""
    chapter = entry[:chapter_or_episode]
    pages = entry[:page_range]
    pages = if pages in [nil, "", "n/a"], do: nil, else: pages

    base = %Citation{work: "theology:#{author}", label: work}

    cond do
      present?(entry[:url]) ->
        %{
          base
          | label: Enum.join(Enum.reject([work, chapter], &blank?/1), ", "),
            url: entry[:url],
            locator: pages
        }

      book = @books[work] ->
        locator = if present?(chapter), do: "on #{chapter}", else: pages
        %{base | label: Citation.book_text(book, locator), book: book, locator: locator}

      true ->
        %{base | work: "studybible", label: work, url: @studybible, locator: chapter}
    end
  end

  @doc "A scholarly source an ANE entry names, as the entry gives it (free text, a book)."
  @spec ane_source(String.t()) :: Citation.t()
  def ane_source(text), do: %Citation{work: "ane", label: text, locator: text}

  @doc "A textual-variant witness or author's claim: its stored citation and URL."
  @spec textual(String.t(), String.t() | nil) :: Citation.t()
  def textual(citation, url \\ nil) do
    %Citation{work: "textual", label: citation, locator: citation, url: blank_nil(url)}
  end

  @doc """
  One of the 26 "HLT" renderings: an unpublished draft (AI-assisted, not
  Heiser's), with its verse's originals: the Hebrew on STEP (THOT), the
  Greek on STEP (LXX), and `witnesses`, any Dead Sea Scroll citations
  (`dss_manuscript/3`).
  """
  @spec hlt(verse(), [Citation.t()]) :: Citation.t()
  def hlt(verse, witnesses \\ []) do
    hebrew = step(verse)
    greek = lxx(verse)

    original =
      [%{label: "Hebrew (MT)", url: hebrew.url}, %{label: "Greek (LXX)", url: greek.url}] ++
        for(
          %Citation{url: url, label: label} <- witnesses,
          url != nil,
          do: %{label: label, url: url}
        )

    %Citation{
      work: "hlt",
      label:
        "Unpublished draft rendering of #{String.replace_suffix(hebrew.label, " (Hebrew)", "")}",
      locator: hebrew.locator,
      translation: :unpublished_draft,
      original: original
    }
  end

  @doc "Fee and Stuart's *How to Read the Bible for All Its Worth*, on a genre."
  @spec fee_stuart(String.t() | nil) :: Citation.t()
  def fee_stuart(genre \\ nil) do
    locator = if present?(genre), do: "on #{genre}"

    %Citation{
      work: "fee_stuart",
      label: Citation.book_text(@fee_stuart, locator),
      book: @fee_stuart,
      locator: locator
    }
  end

  @doc "A research site from `list_research_sources`' catalogue (its string-keyed key, name and url)."
  @spec research(map()) :: Citation.t()
  def research(source),
    do: %Citation{
      work: "research",
      label: source["name"],
      locator: source["key"],
      url: source["url"]
    }

  # ── Lists ────────────────────────────────────────────────────────────────

  @doc "The title a sources list groups a work under."
  @spec work_title(String.t()) :: String.t()
  def work_title("theology:" <> author), do: theology_author(author)
  def work_title(work), do: Map.get(@titles, work, work)

  defp theology_author("heiser"), do: "Michael S. Heiser"
  defp theology_author("owen"), do: "John Owen"
  defp theology_author("stott"), do: "John Stott"
  defp theology_author("lennox"), do: "John C. Lennox"
  defp theology_author("bradley"), do: "Bradley"
  defp theology_author(other), do: other

  @doc "Citations without repeats (same URL, or same work and locator), first first."
  @spec dedupe([Citation.t()]) :: [Citation.t()]
  def dedupe(citations), do: Enum.uniq_by(citations, &Citation.key/1)

  @doc """
  Marks each citation `cited` when `text` (a reply) links it: its whole URL
  is in the text (as written, or percent-encoded or decoded; John 3:1's
  page isn't cited by a link to John 3:16's), or for a book with no URL,
  its title is.
  """
  @spec mark([Citation.t()], String.t() | nil) :: [Citation.t()]
  def mark(citations, text) do
    text = text || ""
    decoded = safe_decode(text)
    Enum.map(citations, &%{&1 | cited: cited?(&1, text, decoded)})
  end

  defp cited?(%Citation{url: url}, text, decoded) when is_binary(url) do
    variants = Enum.uniq([url, safe_decode(url), URI.encode(url)])
    Enum.any?(variants, &(contains_url?(text, &1) or contains_url?(decoded, &1)))
  end

  defp cited?(%Citation{book: %{} = book}, text, _decoded) do
    title = book[:title]
    present?(title) and String.contains?(text, title)
  end

  defp cited?(_citation, _text, _decoded), do: false

  # `url` in `text`, not as the start of a longer URL.
  defp contains_url?(text, url) do
    text
    |> :binary.matches(url)
    |> Enum.any?(fn {at, length} ->
      url_end?(binary_part(text, at + length, byte_size(text) - at - length))
    end)
  end

  defp url_end?(<<c, _::binary>>) when c in ?a..?z or c in ?A..?Z or c in ?0..?9, do: false
  defp url_end?(<<c, _::binary>>) when c in ~c"/#?%+-_=&:~", do: false
  defp url_end?(_rest), do: true

  @doc "Citations grouped by work, in order of first use: `[{work, title, citations}]`."
  @spec by_work([Citation.t()]) :: [{String.t(), String.t(), [Citation.t()]}]
  def by_work(citations) do
    citations
    |> Enum.group_by(& &1.work)
    |> Enum.map(fn {work, group} -> {work, work_title(work), group} end)
    |> Enum.sort_by(fn {work, _, _} -> Enum.find_index(citations, &(&1.work == work)) end)
  end

  @doc """
  A tool's answer with its citations, as rho takes it: the Markdown for
  the model, and `result` with `:citations` for the host's screens.
  """
  @spec details(String.t(), map(), [Citation.t()]) :: {:ok, {:details, String.t(), map()}}
  def details(markdown, result, citations),
    do: {:ok, {:details, markdown, Map.put(result, :citations, dedupe(citations))}}

  # ── Helpers ──────────────────────────────────────────────────────────────

  defp translated(citation, true), do: citation

  defp translated(citation, false) do
    original =
      if citation.url, do: [%{label: citation.label, url: citation.url}], else: []

    %{citation | translation: :assistant, original: original}
  end

  defp step_url(version, book, chapter, verse),
    do:
      "https://www.stepbible.org/?q=version=#{version}@reference=#{book}.#{chapter}.#{max(verse, 1)}"

  defp aquifer_url(dataset, file, title, content_id) do
    {repo, commit} = @aquifer[dataset]

    anchor =
      Patterns.get(:github_anchor_strip)
      |> Regex.replace(String.downcase("#{title} (id: #{content_id})"), "")
      |> String.replace(" ", "-")

    "https://github.com/BibleAquifer/#{repo}/blob/#{commit}/eng/md/#{file}.content.md##{anchor}"
  end

  # A title's filing letter: its first, past a leading "The ".
  defp initial(title) do
    title = String.trim(title)

    title =
      if String.downcase(String.slice(title, 0, 4)) == "the ",
        do: String.slice(title, 4..-1//1),
        else: title

    title |> String.upcase() |> String.to_charlist() |> List.first(?A)
  end

  defp biblehub_slug("Sng", _name), do: "songs"
  defp biblehub_slug(_book, name), do: name |> String.downcase() |> String.replace(" ", "_")

  defp parse({book, chapter, verse}), do: {book, chapter, verse}

  defp parse(reference) when is_binary(reference) do
    [book, chapter, verse | _] = String.split(reference, ".")
    {book, String.to_integer(chapter), leading_integer(verse)}
  end

  defp leading_integer(text) do
    {n, _rest} = Integer.parse(text)
    n
  end

  defp bbcccvvv(<<book::binary-size(2), chapter::binary-size(3), verse::binary-size(3)>>),
    do: {String.to_integer(book), String.to_integer(chapter), String.to_integer(verse)}

  # "Genesis 10:1", "Avodah Zarah 1:1–2", "4 Ezra 10:1": {name, chapter, verse}.
  defp verse_of(text) do
    {name, place} =
      case String.split(text, " ") do
        [_one] -> {"", text}
        words -> {words |> Enum.drop(-1) |> Enum.join(" "), List.last(words)}
      end

    [chapter, verse] = String.split(first_locator(place), ":")
    {name, String.to_integer(chapter), String.to_integer(verse)}
  end

  # The first section of a locator: "18.63–64" → "18.63", "1.104" → "1.104",
  # "101" → "101", "Antiquities 1.104–108" → "1.104".
  defp first_locator(text) do
    place = text |> String.split(" ") |> List.last()

    case Regex.run(Patterns.get(:first_locator), place) do
      [match] -> match
      nil -> place
    end
  end

  defp strongs_number(strongs) do
    case Regex.run(Patterns.get(:citation_strongs), String.upcase(String.trim(strongs))) do
      [_, letter, digits | _] -> {letter, String.to_integer(digits)}
      nil -> raise ArgumentError, "not a Strong's number: #{inspect(strongs)}"
    end
  end

  # strongs ("G26") → {printed page, the Internet Archive's page token}.
  defp abbott_smith_page(strongs) do
    case @abbott_smith_pages[strongs] do
      nil -> nil
      page -> {page, Map.get(@abbott_smith_tokens, page, page)}
    end
  end

  defp safe_decode(text) do
    URI.decode(text)
  rescue
    ArgumentError -> text
  end

  defp present?(value), do: value not in [nil, ""]
  defp blank?(value), do: value in [nil, ""]
  defp blank_nil(value), do: if(blank?(value), do: nil, else: value)
end
