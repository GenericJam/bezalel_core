defmodule Bezalel.Study.Ancient.Fathers do
  @moduledoc """
  The Apostolic Fathers, the `apostolic_fathers` corpus of the fathers pack
  (`Bezalel.Study.Ancient.Registry` appends `corpus/0`; every work carries
  `pack: :fathers`, `Bezalel.Study.Ancient.pack/1`).

  The Greek (Latin where only a Latin version survives) is Kirsopp Lake's
  text (Loeb, 1912–1913) as corrected by James Tauber and Seumas Macdonald,
  *Open Apostolic Fathers* 1.0 (2019); the English is CAFE, the
  *Contemporary Apostolic Fathers Edition* (James Cuénod, 2024), a machine
  translation: GPT-4o's first drafts, published without systematic human
  revision. Every passage says so (`edition`, `translation`, its tag and
  its citation, `Bezalel.Study.Citations.ancient/3`). Both are CC BY-SA 4.0.
  `mix bezalel.data.fathers` builds the pack; why these sources, the
  numbering and the dates: `decisions/2026-10-22-apostolic-fathers-pack.md`.

  Each work is cited as Lake numbers it: chapter.verse ('Didache 9.1', '1
  Clement 5.4', 'Ignatius, To the Ephesians 20.2'); the Shepherd of Hermas
  as three works, Visions, Mandates and Similitudes, each by
  book.chapter.verse ('Hermas, Vision 1.1.1', 'Mandate 4.1.1', 'Similitude
  9.30.5'); the Moscow manuscript's epilogue to the Martyrdom of Polycarp by
  its section ('Martyrdom of Polycarp, Moscow epilogue 1'). Chapter 0 is a
  work's title or salutation ('Didache 0.1').

  Dates are scholarly ranges, attributed: Bart D. Ehrman's introductions to
  the Loeb *Apostolic Fathers* (2003) unless the tag names another source
  (the decision record quotes them). Tiers as `Bezalel.Study.Ancient.Registry`'s:
  `A/B` where a work is generally dated before c. AD 100 and the date is
  disputed (1 Clement, the Didache).
  """

  @edition "Lake's Greek, corrected (Tauber–Macdonald); CAFE machine-translated English"

  @chapter %{
    name: "chapter.verse",
    depth: 2,
    separator: ".",
    books: nil,
    example: "1.1",
    roman: false,
    scale: 1000
  }

  @not_scripture "Not Scripture"
  @alexandrinus "Not Scripture in any canon today; copied after Revelation in Codex Alexandrinus (5th c.)"
  @sinaiticus "Not Scripture in any canon today; copied after Revelation in Codex Sinaiticus (4th c.)"
  @sinaiticus_hermas "Not Scripture in any canon today; copied in part after Revelation and Barnabas in Codex Sinaiticus (4th c.)"

  # Dates: Bart D. Ehrman's introductions, The Apostolic Fathers (Loeb
  # Classical Library 24–25, 2003), unless the decision record says otherwise.
  @ehrman "Ehrman, Loeb 2003"
  @ignatius_date "c. AD 110, midway through Trajan's reign, 98–117, as Eusebius dates his martyrdom; later dates proposed (#{@ehrman})"

  @works [
    %{
      key: "1_clement",
      title: "1 Clement",
      reference_title: "1 Clement",
      aliases: ["1 Clem.", "I Clement", "First Clement", "First Epistle of Clement"],
      status: @alexandrinus,
      kind: "early Christian letter, from the church at Rome to Corinth",
      date:
        "c. AD 95–96 traditionally, near the end of the 1st c.; firm limits c. 64–170 (#{@ehrman})",
      tier: "A/B"
    },
    %{
      key: "2_clement",
      title: "2 Clement",
      reference_title: "2 Clement",
      aliases: ["2 Clem.", "II Clement", "Second Clement", "Second Epistle of Clement"],
      status: @alexandrinus,
      kind: "early Christian sermon",
      date: "mid-2nd c., possibly the 140s (#{@ehrman})",
      tier: "B"
    },
    %{
      key: "ignatius_ephesians",
      title: "Ignatius of Antioch, To the Ephesians",
      reference_title: "Ignatius, To the Ephesians",
      aliases: ["Ign. Eph.", "Ignatius, Ephesians", "Ignatius of Antioch, Ephesians"],
      status: @not_scripture,
      kind: "early Christian letter",
      date: @ignatius_date,
      tier: "B"
    },
    %{
      key: "ignatius_magnesians",
      title: "Ignatius of Antioch, To the Magnesians",
      reference_title: "Ignatius, To the Magnesians",
      aliases: ["Ign. Magn.", "Ign. Mag.", "Ignatius, Magnesians"],
      status: @not_scripture,
      kind: "early Christian letter",
      date: @ignatius_date,
      tier: "B"
    },
    %{
      key: "ignatius_trallians",
      title: "Ignatius of Antioch, To the Trallians",
      reference_title: "Ignatius, To the Trallians",
      aliases: ["Ign. Trall.", "Ign. Tral.", "Ignatius, Trallians"],
      status: @not_scripture,
      kind: "early Christian letter",
      date: @ignatius_date,
      tier: "B"
    },
    %{
      key: "ignatius_romans",
      title: "Ignatius of Antioch, To the Romans",
      reference_title: "Ignatius, To the Romans",
      aliases: ["Ign. Rom.", "Ignatius, Romans"],
      status: @not_scripture,
      kind: "early Christian letter",
      date: @ignatius_date,
      tier: "B"
    },
    %{
      key: "ignatius_philadelphians",
      title: "Ignatius of Antioch, To the Philadelphians",
      reference_title: "Ignatius, To the Philadelphians",
      aliases: ["Ign. Phld.", "Ign. Phil.", "Ignatius, Philadelphians"],
      status: @not_scripture,
      kind: "early Christian letter",
      date: @ignatius_date,
      tier: "B"
    },
    %{
      key: "ignatius_smyrnaeans",
      title: "Ignatius of Antioch, To the Smyrnaeans",
      reference_title: "Ignatius, To the Smyrnaeans",
      aliases: ["Ign. Smyrn.", "Ignatius, Smyrnaeans"],
      status: @not_scripture,
      kind: "early Christian letter",
      date: @ignatius_date,
      tier: "B"
    },
    %{
      key: "ignatius_polycarp",
      title: "Ignatius of Antioch, To Polycarp",
      reference_title: "Ignatius, To Polycarp",
      aliases: ["Ign. Pol.", "Ignatius, Polycarp"],
      status: @not_scripture,
      kind: "early Christian letter",
      date: @ignatius_date,
      tier: "B"
    },
    %{
      key: "polycarp_philippians",
      title: "Polycarp of Smyrna, To the Philippians",
      reference_title: "Polycarp, To the Philippians",
      aliases: [
        "Pol. Phil.",
        "Polycarp, Philippians",
        "Letter of Polycarp to the Philippians",
        "Epistle of Polycarp"
      ],
      status: @not_scripture,
      kind: "early Christian letter; chapters 10–12 and 14 survive only in Latin",
      date:
        "c. AD 110–135: most read it as two letters, ch. 13 c. 110 and chs. 1–12 some 20–25 years later (#{@ehrman})",
      tier: "B"
    },
    %{
      key: "martyrdom_of_polycarp",
      title: "Martyrdom of Polycarp",
      reference_title: "Martyrdom of Polycarp",
      aliases: ["Mart. Pol.", "Martyrdom of Saint Polycarp"],
      status: @not_scripture,
      kind: "early Christian martyr account, from the church at Smyrna",
      date: "most date it 155 or 156; others the late 160s or 177 (#{@ehrman})",
      tier: "B"
    },
    %{
      key: "martyrdom_of_polycarp_moscow_epilogue",
      title: "Martyrdom of Polycarp, Moscow epilogue",
      reference_title: "Martyrdom of Polycarp, Moscow epilogue",
      aliases: ["Mart. Pol. Moscow epilogue", "Moscow epilogue"],
      status: @not_scripture,
      kind: "an epilogue on the account's copying, in the Moscow manuscript only",
      date: "later than the account; undated",
      tier: "B",
      locator: %{
        name: "section",
        depth: 1,
        separator: ".",
        books: nil,
        example: "1",
        roman: false,
        scale: 1000
      }
    },
    %{
      key: "didache",
      title: "Didache",
      reference_title: "Didache",
      aliases: ["Did.", "Teaching of the Twelve Apostles", "The Didache"],
      status: @not_scripture,
      kind: "early Christian church manual",
      date:
        "c. AD 100, possibly a decade or so later, from sources perhaps of the mid-1st c. (#{@ehrman}); others date it to the 2nd c.",
      tier: "A/B"
    },
    %{
      key: "barnabas",
      title: "Epistle of Barnabas",
      reference_title: "Barnabas",
      aliases: ["Barn.", "Letter of Barnabas", "Pseudo-Barnabas"],
      status: @sinaiticus,
      kind: "early Christian treatise in letter form",
      date: "c. AD 130, Ehrman; after the temple's fall in AD 70",
      tier: "B"
    },
    %{
      key: "hermas_visions",
      title: "Shepherd of Hermas, Visions",
      reference_title: "Hermas, Vision",
      aliases: [
        "Herm. Vis.",
        "Hermas, Visions",
        "Shepherd of Hermas, Vision",
        "Shepherd, Vision",
        "Vision",
        "Visions",
        "Vis."
      ],
      status: @sinaiticus_hermas,
      kind: "early Christian apocalypse",
      date: "perhaps AD 110–140, possibly written over time (#{@ehrman})",
      tier: "B",
      locator: %{
        name: "vision.chapter.verse",
        depth: 3,
        separator: ".",
        books: 5,
        example: "1.1.1",
        roman: true,
        scale: 1000
      }
    },
    %{
      key: "hermas_mandates",
      title: "Shepherd of Hermas, Mandates",
      reference_title: "Hermas, Mandate",
      aliases: [
        "Herm. Mand.",
        "Hermas, Mandates",
        "Hermas, Commandment",
        "Shepherd of Hermas, Mandate",
        "Shepherd, Mandate",
        "Mandate",
        "Mandates",
        "Mand."
      ],
      status: @sinaiticus_hermas,
      kind: "early Christian apocalypse",
      date: "perhaps AD 110–140, possibly written over time (#{@ehrman})",
      tier: "B",
      locator: %{
        name: "mandate.chapter.verse",
        depth: 3,
        separator: ".",
        books: 12,
        example: "4.1.1",
        roman: true,
        scale: 1000
      }
    },
    %{
      key: "hermas_similitudes",
      title: "Shepherd of Hermas, Similitudes",
      reference_title: "Hermas, Similitude",
      aliases: [
        "Herm. Sim.",
        "Hermas, Similitudes",
        "Hermas, Parable",
        "Shepherd of Hermas, Similitude",
        "Shepherd, Similitude",
        "Similitude",
        "Similitudes",
        "Sim."
      ],
      status: @sinaiticus_hermas,
      kind: "early Christian apocalypse; much of 9.30–10.4 survives only in Latin",
      date: "perhaps AD 110–140, possibly written over time (#{@ehrman})",
      tier: "B",
      locator: %{
        name: "similitude.chapter.verse",
        depth: 3,
        separator: ".",
        books: 10,
        example: "9.1.1",
        roman: true,
        scale: 1000
      }
    },
    %{
      key: "diognetus",
      title: "Epistle to Diognetus",
      reference_title: "Diognetus",
      aliases: ["Diogn.", "To Diognetus", "Letter to Diognetus"],
      status: @not_scripture,
      kind: "early Christian apology in letter form",
      date: "AD 150–310 broadly; probably the second half of the 2nd c. (#{@ehrman})",
      tier: "B"
    }
  ]

  @corpus %{
    label: "Apostolic Fathers",
    tag: nil,
    aliases: ["Apostolic Fathers"],
    key: "apostolic_fathers",
    caveat:
      "Early Christian writings of the late 1st and 2nd c. AD (Diognetus perhaps later; each " <>
        "passage's tag gives its work's date, most of them disputed), in Kirsopp Lake's Greek " <>
        "as corrected by James Tauber and " <>
        "Seumas Macdonald, with the Latin where only a Latin version survives. The English is " <>
        "CAFE's machine translation (GPT-4o drafts, published without systematic human " <>
        "revision), not a published human translation: check it against the Greek, and say " <>
        "it is machine-made when you quote it.",
    verdict: nil,
    example_citation: "Didache 9.1",
    heading_label: "Editorial heading",
    line_numbered: false,
    no_english_note: "No English translation included",
    original_language: "Greek",
    periods: ["roman"]
  }

  @doc "The `apostolic_fathers` corpus, its works in Lake's order."
  @spec corpus() :: map()
  def corpus, do: Map.put(@corpus, :works, Enum.map(@works, &work/1))

  @doc "The work keys, in registry order."
  @spec work_keys() :: [String.t()]
  def work_keys, do: Enum.map(@works, & &1.key)

  defp work(entry) do
    %{
      tag: %{
        status: entry.status,
        date: entry.date,
        kind: entry.kind,
        edition: @edition,
        manuscript: nil,
        sections: [],
        tier: entry.tier
      },
      title: entry.title,
      aliases: entry.aliases,
      key: entry.key,
      collection: nil,
      coverage_note: "",
      locator: Map.get(entry, :locator, @chapter),
      reference_title: entry.reference_title,
      pack: :fathers,
      author: author(entry.key)
    }
  end

  # A passage's author line: the traditional attribution, marked as such.
  defp author("1_clement"), do: "Church of Rome (attributed to Clement)"
  defp author("2_clement"), do: "Anonymous (attributed to Clement of Rome)"
  defp author("ignatius_" <> _), do: "Ignatius"
  defp author("polycarp_philippians"), do: "Polycarp"
  defp author("martyrdom_of_polycarp" <> _), do: "Church of Smyrna"
  defp author("barnabas"), do: "Anonymous (attributed to Barnabas)"
  defp author("hermas_" <> _), do: "Hermas"
  defp author(_didache_or_diognetus), do: "Anonymous"
end
