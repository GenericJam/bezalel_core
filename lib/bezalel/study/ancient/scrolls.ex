defmodule Bezalel.Study.Ancient.Scrolls do
  @moduledoc """
  The Qumran manuscripts of the scrolls pack, as registry works of the
  `qumran` corpus (`Bezalel.Study.Ancient.Registry` appends `works/0` to
  CD, 1QS, 1QSa and 1QpHab, which stay in the ancient pack).

  Each manuscript of a major non-biblical work is a work of its own, cited
  by its ETCBC/dss siglum ('4Q174 1–2 i 10', '1QM 5:3') or its conventional
  name ('4QFlor', '4QMMTa'); a composition with several copies is their
  collection ('Songs of the Sabbath Sacrifice 4Q405 23 ii 1'), and copies are
  never merged into a composite. Which works count as major, and why, is
  `decisions/2026-10-18-dead-sea-scrolls-pack.md`. The pack's rows carry each
  manuscript's text as ETCBC transcribes it (`mix bezalel.data.scrolls`, which
  reads this list to know what to import).

  Every work has extra keys the other corpora's works lack:

    * `pack: :scrolls`: the pack its passages are in;
    * `siglum`: the ETCBC/dss scroll label (`4Q223_224` for the work cited
      '4Q223–224');
    * `composition`: the composition's title (a passage's author line);
    * `name`: the manuscript's conventional name ('4QDa'), or nil;
    * `periods`: the passages' period tags.

  Their locator is `fragment_locator/0`: an ETCBC fragment or column label
  and an optional line or line range, resolved against the pack.

  Copy dates are the script period of the Leon Levy Dead Sea Scrolls Digital
  Library's manuscript page (Israel Antiquities Authority,
  deadseascrolls.org.il/explore-the-archive/manuscript/<siglum>-1), with
  Cross's conventional ranges (Hasmonean c. 150–30 BC, Herodian c. 30 BC–AD
  68); none where the library gives none. Composition dates are the general
  consensus of the handbooks, not one source's (the decision record lists
  them as unverified).
  """

  # Hebrew or Aramaic: each passage names its language beside its text.
  @edition "Abegg–Bowley–Cook (ETCBC)"

  @locator %{
    name: "fragment or column and line",
    kind: :fragment,
    depth: 2,
    separator: " ",
    books: nil,
    example: "1 i 5",
    roman: true,
    scale: 1000
  }

  @not_scripture "Not Scripture"
  @enoch_canon "Scripture in the Ethiopian and Eritrean Orthodox Tewahedo canons and for Beta Israel; not in other canons"
  @tobit_canon "Scripture in the Catholic and Orthodox canons, not the Jewish or Protestant ones"

  # Script periods (Leon Levy) as shown.
  @hasmonean "Hasmonean script (c. 150–30 BC)"
  @herodian "Herodian script (c. 30 BC–AD 68)"
  @hellenistic_roman "Hellenistic–Roman period"

  # A copy is {ETCBC siglum, conventional name or nil, copy date or nil}, or
  # with a fourth element replacing the tag's date. The first copy of a
  # `principal: true` composition carries its title and aliases (so 'War
  # Scroll 5:3' is 1QM); every other copy is titled 'Composition (name)'.
  # A composition with several copies is their collection.
  @compositions [
    %{
      key: "damascus_document",
      title: "Damascus Document",
      aliases: ["4QD"],
      principal: false,
      kind: "Qumran sectarian rule",
      composed: "composed 2nd–1st c. BC",
      status: @not_scripture,
      periods: "second_temple,hasmonean",
      copies: [
        {"4Q266", "4QDa", @hasmonean},
        {"4Q267", "4QDb", @herodian},
        {"4Q268", "4QDc", @herodian},
        {"4Q269", "4QDd", @herodian},
        {"4Q270", "4QDe", @herodian},
        {"4Q271", "4QDf", @herodian},
        {"4Q272", "4QDg", @herodian},
        {"4Q273", "4QpapDh", @herodian},
        {"5Q12", "5QD", @herodian},
        {"6Q15", "6QD", @herodian}
      ]
    },
    %{
      key: "community_rule",
      title: "Community Rule",
      aliases: ["4QS", "Serekh ha-Yahad"],
      principal: false,
      kind: "Qumran sectarian rule",
      composed: "composed c. 100 BC",
      status: @not_scripture,
      periods: "second_temple,hasmonean",
      copies: [
        {"4Q255", "4QpapSa", @hasmonean},
        {"4Q256", "4QSb", @herodian},
        {"4Q257", "4QpapSc", @hasmonean},
        {"4Q258", "4QSd", @herodian},
        {"4Q259", "4QSe", @herodian},
        {"4Q260", "4QSf", @herodian},
        {"4Q261", "4QSg", @herodian},
        {"4Q262", "4QSh", @herodian},
        {"4Q263", "4QSi", @herodian},
        {"4Q264", "4QSj", @herodian},
        {"5Q11", "5QS", @herodian}
      ]
    },
    %{
      key: "rule_of_blessings",
      title: "Rule of Blessings",
      aliases: ["1Q28b", "Rule of Benedictions", "Blessings"],
      principal: true,
      kind: "Qumran sectarian liturgy",
      composed: "composed c. 100 BC",
      status: @not_scripture,
      periods: "second_temple,hasmonean",
      # Copied on the same scroll as 1QS and 1QSa: their date, as the ancient pack tags them.
      copies: [{"1QSb", "1QSb", nil, "c. 100 BC; Cave 1 copy c. 75 BC"}]
    },
    %{
      key: "war_scroll",
      title: "War Scroll",
      aliases: [
        "War Rule",
        "Milhamah",
        "War of the Sons of Light against the Sons of Darkness",
        "1Q33"
      ],
      principal: true,
      kind: "Qumran sectarian rule",
      composed: "composed 2nd–1st c. BC",
      status: @not_scripture,
      periods: "second_temple,hasmonean",
      copies: [
        {"1QM", "1QM", nil, nil},
        {"4Q491", "4QMa", @herodian},
        {"4Q492", "4QMb", @herodian},
        {"4Q493", "4QMc", @herodian},
        {"4Q494", "4QMd", @herodian},
        {"4Q495", "4QMe", @hasmonean},
        {"4Q496", "4QpapMf", @hasmonean}
      ]
    },
    %{
      key: "hodayot",
      title: "Hodayot",
      aliases: ["Thanksgiving Hymns", "Thanksgiving Scroll", "1QH"],
      principal: true,
      kind: "Qumran sectarian hymns",
      composed: "composed c. 100 BC",
      status: @not_scripture,
      periods: "second_temple,hasmonean",
      copies: [
        {"1QHa", "1QHa", nil, nil},
        {"1Q35", "1QHb", @herodian},
        {"4Q427", "4QHa", @herodian},
        {"4Q428", "4QHb", @hasmonean},
        {"4Q429", "4QHc", @herodian},
        {"4Q430", "4QHd", @herodian},
        {"4Q431", "4QHe", @herodian},
        {"4Q432", "4QpapHf", @herodian}
      ]
    },
    %{
      key: "temple_scroll",
      title: "Temple Scroll",
      aliases: ["11QT", "Megillat ha-Miqdash"],
      principal: true,
      kind: "rewritten Torah law",
      composed: "composed c. 150–100 BC",
      status: @not_scripture,
      periods: "second_temple,hasmonean",
      copies: [
        {"11Q19", "11QTa", nil, nil},
        {"11Q20", "11QTb", @herodian},
        {"11Q21", "11QTc?", @herodian},
        {"4Q524", nil, @hasmonean}
      ]
    },
    %{
      key: "mmt",
      title: "Miqsat Ma'ase ha-Torah",
      aliases: ["4QMMT", "MMT", "Halakhic Letter", "Some Works of the Torah"],
      principal: false,
      kind: "Qumran sectarian legal letter",
      composed: "composed c. 150 BC",
      status: @not_scripture,
      periods: "second_temple,hasmonean",
      copies: [
        {"4Q394", "4QMMTa", @herodian},
        {"4Q395", "4QMMTb", @herodian},
        {"4Q396", "4QMMTc", @herodian},
        {"4Q397", "4QMMTd", @herodian},
        {"4Q398", "4QpapMMTe", @herodian},
        {"4Q399", "4QMMTf", @herodian}
      ]
    },
    %{
      key: "florilegium",
      title: "Florilegium",
      aliases: ["4QFlor", "4QMidrEschata", "Eschatological Midrash"],
      principal: true,
      kind: "Qumran thematic pesher",
      composed: "composed 1st c. BC",
      status: @not_scripture,
      periods: "second_temple,hasmonean,roman",
      copies: [{"4Q174", "4QFlor", @herodian}]
    },
    %{
      key: "testimonia",
      title: "Testimonia",
      aliases: ["4QTest", "Messianic Anthology"],
      principal: true,
      kind: "Qumran exegetical anthology",
      composed: "composed c. 100 BC",
      status: @not_scripture,
      periods: "second_temple,hasmonean",
      copies: [{"4Q175", "4QTest", @herodian}]
    },
    %{
      key: "melchizedek",
      title: "Melchizedek",
      aliases: ["11QMelch", "Melchizedek Midrash"],
      principal: true,
      kind: "Qumran thematic pesher",
      composed: "composed 2nd–1st c. BC",
      status: @not_scripture,
      periods: "second_temple,hasmonean",
      copies: [{"11Q13", "11QMelch", @hasmonean}]
    },
    %{
      key: "aramaic_apocalypse",
      title: "Aramaic Apocalypse",
      aliases: ["Son of God Text", "Apocryphon of Daniel", "4QapocrDan ar"],
      principal: true,
      kind: "Aramaic apocalyptic",
      composed: "composed 2nd–1st c. BC",
      status: @not_scripture,
      periods: "second_temple,hasmonean",
      copies: [{"4Q246", "4QapocrDan ar", @herodian}]
    },
    %{
      key: "messianic_apocalypse",
      title: "Messianic Apocalypse",
      aliases: ["4QMessAp", "On Resurrection"],
      principal: true,
      kind: "Second Temple apocalyptic poetry",
      composed: "composed c. 100–80 BC",
      status: @not_scripture,
      periods: "second_temple,hasmonean",
      copies: [{"4Q521", nil, @hasmonean}]
    },
    %{
      key: "pesher_nahum",
      title: "Pesher Nahum",
      aliases: ["4QpNah", "Nahum Pesher", "Nahum Commentary"],
      principal: true,
      kind: "Qumran pesher",
      composed: "composed after 63 BC",
      status: @not_scripture,
      periods: "second_temple,hasmonean,roman",
      copies: [{"4Q169", "4QpNah", @herodian}]
    },
    %{
      key: "pesher_psalms",
      title: "Pesher Psalms",
      aliases: ["4QpPsa", "Psalms Pesher", "Psalms Commentary"],
      principal: true,
      kind: "Qumran pesher",
      composed: "composed 1st c. BC",
      status: @not_scripture,
      periods: "second_temple,hasmonean,roman",
      copies: [{"4Q171", "4QpPsa", @herodian}]
    },
    %{
      key: "pesher_isaiah",
      title: "Pesher Isaiah",
      aliases: ["4QpIsa", "Isaiah Pesher", "Isaiah Commentary"],
      principal: false,
      kind: "Qumran pesher",
      composed: "composed 1st c. BC",
      status: @not_scripture,
      periods: "second_temple,hasmonean,roman",
      copies: [
        {"4Q161", "4QpIsaa", @herodian},
        {"4Q162", "4QpIsab", @herodian},
        {"4Q163", "4Qpap pIsac", @hasmonean},
        {"4Q164", "4QpIsad", @hasmonean},
        {"4Q165", "4QpIsae", @herodian}
      ]
    },
    %{
      key: "songs_of_the_sabbath_sacrifice",
      title: "Songs of the Sabbath Sacrifice",
      aliases: ["ShirShabb", "Angelic Liturgy"],
      principal: false,
      kind: "Second Temple liturgy",
      composed: "composed c. 100–50 BC",
      status: @not_scripture,
      periods: "second_temple,hasmonean",
      copies: [
        {"4Q400", "4QShirShabba", @hasmonean},
        {"4Q401", "4QShirShabbb", @herodian},
        {"4Q402", "4QShirShabbc", @herodian},
        {"4Q403", "4QShirShabbd", @herodian},
        {"4Q404", "4QShirShabbe", @herodian},
        {"4Q405", "4QShirShabbf", @hasmonean},
        {"4Q406", "4QShirShabbg", @hellenistic_roman},
        {"4Q407", "4QShirShabbh", @hasmonean},
        {"11Q17", "11QShirShabb", @herodian}
      ]
    },
    %{
      key: "genesis_apocryphon",
      title: "Genesis Apocryphon",
      aliases: ["1QapGen", "1QapGen ar"],
      principal: true,
      kind: "Aramaic rewritten Bible",
      composed: "composed 2nd–1st c. BC",
      status: @not_scripture,
      periods: "second_temple,hasmonean",
      copies: [{"1Q20", "1QapGen ar", @herodian}]
    },
    %{
      key: "aramaic_enoch",
      title: "Aramaic Enoch",
      aliases: ["4QEn", "Qumran Enoch"],
      principal: false,
      kind: "Aramaic apocalyptic (1 Enoch)",
      composed: "composed 3rd–2nd c. BC",
      status: @enoch_canon,
      periods: "second_temple",
      copies: [
        {"4Q201", "4QEna ar", @hasmonean},
        {"4Q202", "4QEnb ar", @hasmonean},
        {"4Q204", "4QEnc ar", @herodian},
        {"4Q205", "4QEnd ar", @herodian},
        {"4Q206", "4QEne ar", nil},
        {"4Q207", "4QEnf ar", @hellenistic_roman},
        {"4Q212", "4QEng ar", @hasmonean},
        {"4Q208", "4QEnastra ar", "pre-Hasmonean script (before c. 150 BC)"},
        {"4Q209", "4QEnastrb ar", @herodian},
        {"4Q210", "4QEnastrc ar", @hasmonean},
        {"4Q211", "4QEnastrd ar", @hasmonean}
      ]
    },
    %{
      key: "book_of_giants",
      title: "Book of Giants",
      aliases: ["EnGiants", "Giants"],
      principal: false,
      kind: "Aramaic apocalyptic (Enochic)",
      composed: "composed 3rd–2nd c. BC",
      status: @not_scripture,
      periods: "second_temple",
      copies: [
        {"1Q23", "1QEnGiantsa ar", @hasmonean},
        {"1Q24", "1QEnGiantsb? ar", @hellenistic_roman},
        {"2Q26", "2QEnGiants ar", @herodian},
        {"4Q203", "4QEnGiantsa ar", @herodian},
        {"4Q530", "4QEnGiantsb ar", @hasmonean},
        {"4Q531", "4QEnGiantsc ar", @hasmonean},
        {"4Q532", "4QEnGiantsd ar", @hasmonean},
        {"4Q533", "4QEnGiantse? ar", @hasmonean},
        {"6Q8", "6QpapGiants ar", @herodian}
      ]
    },
    %{
      key: "aramaic_levi",
      title: "Aramaic Levi Document",
      aliases: ["Aramaic Levi", "ALD", "Aramaic Testament of Levi"],
      principal: false,
      kind: "Aramaic pseudepigraphon",
      composed: "composed 3rd–2nd c. BC",
      status: @not_scripture,
      periods: "second_temple",
      copies: [
        {"1Q21", "1QLevi ar", @hasmonean},
        {"4Q213", "4QLevia ar", nil},
        {"4Q213a", "4QLevib ar", @hasmonean},
        {"4Q213b", "4QLevic ar", nil},
        {"4Q214", "4QLevid ar", nil},
        {"4Q214a", "4QLevie ar", nil},
        {"4Q214b", "4QLevif ar", nil}
      ]
    },
    %{
      key: "instruction",
      title: "Instruction",
      aliases: ["4QInstruction", "Musar le-Mevin", "Sapiential Work A"],
      principal: false,
      kind: "wisdom instruction",
      composed: "composed 2nd c. BC",
      status: @not_scripture,
      periods: "second_temple,hasmonean",
      copies: [
        {"1Q26", "1QInstruction", @hasmonean},
        {"4Q415", "4QInstructiona", @herodian},
        {"4Q416", "4QInstructionb", @herodian},
        {"4Q417", "4QInstructionc", @herodian},
        {"4Q418", "4QInstructiond", @herodian},
        {"4Q418a", "4QInstructione", nil},
        {"4Q418c", "4QInstructionf?", nil},
        {"4Q423", "4QInstructiong", @herodian}
      ]
    },
    %{
      key: "commentary_on_genesis_a",
      title: "Commentary on Genesis A",
      aliases: ["4QCommGen A", "Genesis Pesher", "Patriarchal Blessings"],
      principal: true,
      kind: "Qumran exegetical commentary",
      composed: "composed 1st c. BC",
      status: @not_scripture,
      periods: "second_temple,hasmonean,roman",
      copies: [{"4Q252", "4QCommGen A", @herodian}]
    },
    %{
      key: "sefer_ha_milhamah",
      title: "Sefer ha-Milhamah",
      aliases: ["Book of War"],
      principal: false,
      kind: "Qumran sectarian rule",
      composed: "composed 1st c. BC",
      status: @not_scripture,
      periods: "second_temple,hasmonean",
      copies: [
        {"4Q285", "4QSefer ha-Milhamah", @herodian},
        {"11Q14", "11QSefer ha-Milhamah", @herodian}
      ]
    },
    %{
      key: "catena_a",
      title: "Catena A",
      aliases: ["4QCatena A", "4QMidrEschatb"],
      principal: true,
      kind: "Qumran thematic pesher",
      composed: "composed 1st c. BC",
      status: @not_scripture,
      periods: "second_temple,hasmonean,roman",
      copies: [{"4Q177", "4QCatena A", @herodian}]
    },
    %{
      key: "songs_of_the_sage",
      title: "Songs of the Sage",
      aliases: ["Songs of the Maskil", "4QShir"],
      principal: false,
      kind: "Qumran apotropaic poetry",
      composed: "composed 1st c. BC",
      status: @not_scripture,
      periods: "second_temple,hasmonean,roman",
      copies: [{"4Q510", "4QShira", @herodian}, {"4Q511", "4QShirb", @herodian}]
    },
    %{
      key: "copper_scroll",
      title: "Copper Scroll",
      aliases: ["3QTreasure", "3QCopper Scroll"],
      principal: true,
      kind: "treasure list",
      composed: "1st c. AD, debated",
      status: @not_scripture,
      periods: "second_temple,roman",
      copies: [{"3Q15", "3QTreasure", "Roman period"}]
    },
    %{
      key: "jubilees",
      title: "Jubilees",
      aliases: ["Book of Jubilees", "4QJub"],
      principal: false,
      kind: "rewritten Bible",
      composed: "composed c. 160–150 BC",
      status: @enoch_canon,
      periods: "second_temple,hasmonean",
      copies: [
        {"1Q17", "1QJuba", @hellenistic_roman},
        {"1Q18", "1QJubb", @hasmonean},
        {"2Q19", "2QJuba", @herodian},
        {"2Q20", "2QJubb", @herodian},
        {"3Q5", "3QJub", @herodian},
        {"4Q216", "4QJuba", @hasmonean},
        {"4Q218", "4QJubc", @herodian},
        {"4Q219", "4QJubd", @hasmonean},
        {"4Q220", "4QJube", @herodian},
        {"4Q221", "4QJubf", @herodian},
        {"4Q222", "4QJubg", @hasmonean},
        {"4Q223_224", "4QpapJubh", @hasmonean},
        {"11Q12", "11QJub", @herodian}
      ]
    },
    %{
      key: "tobit",
      title: "Tobit",
      aliases: ["4QTob"],
      principal: false,
      kind: "Jewish narrative",
      composed: "composed c. 225–175 BC",
      status: @tobit_canon,
      periods: "second_temple",
      copies: [
        {"4Q196", "4QpapToba ar", @hasmonean},
        {"4Q197", "4QTobb ar", @herodian},
        {"4Q198", "4QTobc ar", @hasmonean},
        {"4Q199", "4QTobd ar", @hasmonean},
        {"4Q200", "4QTobe", @herodian}
      ]
    },
    %{
      key: "prayer_of_nabonidus",
      title: "Prayer of Nabonidus",
      aliases: ["4QPrNab", "4QPrNab ar"],
      principal: true,
      kind: "Aramaic court tale",
      composed: "composed 3rd–2nd c. BC",
      status: @not_scripture,
      periods: "second_temple",
      copies: [{"4Q242", "4QPrNab ar", @hasmonean}]
    },
    %{
      key: "targum_of_job",
      title: "Targum of Job",
      aliases: ["Job Targum"],
      principal: false,
      kind: "Aramaic translation of Job",
      composed: "translated 2nd–1st c. BC",
      status: @not_scripture,
      periods: "second_temple",
      copies: [{"11Q10", "11QtgJob", @herodian}, {"4Q157", "4QtgJob", @herodian}]
    }
  ]

  @doc "The fragment-and-line locator of every scrolls-pack work."
  @spec fragment_locator() :: map()
  def fragment_locator, do: @locator

  @doc "The compositions, in registry order: key, title, kind, dates, status, periods, copies."
  @spec compositions() :: [map()]
  def compositions, do: @compositions

  @doc "Every manuscript as a registry work, in composition order."
  @spec works() :: [map()]
  def works, do: Enum.flat_map(@compositions, &composition_works/1)

  defp composition_works(composition) do
    several = match?([_, _ | _], composition.copies)

    composition.copies
    |> Enum.with_index()
    |> Enum.map(fn {copy, index} ->
      {siglum, name, copy_date, date_note} = copy(copy)
      principal = composition.principal and index == 0
      cited = String.replace(siglum, "_", "–")

      %{
        tag: %{
          status: composition.status,
          date: date_note || composition.composed,
          kind: composition.kind,
          edition: @edition,
          manuscript: manuscript(name || cited, copy_date),
          sections: [],
          tier: "A"
        },
        title: title(composition, name || cited, principal),
        aliases: aliases(composition, name, principal),
        key: work_key(siglum),
        collection: if(several, do: %{title: composition.title, aliases: composition.aliases}),
        coverage_note: "",
        locator: @locator,
        reference_title: cited,
        pack: :scrolls,
        siglum: siglum,
        composition: composition.title,
        name: name,
        periods: composition.periods
      }
    end)
  end

  defp copy({siglum, name, copy_date}), do: {siglum, name, copy_date, nil}
  defp copy({siglum, name, copy_date, date_note}), do: {siglum, name, copy_date, date_note}

  defp title(composition, _name, true), do: composition.title
  defp title(composition, name, false), do: "#{composition.title} (#{name})"

  defp aliases(composition, name, true), do: Enum.uniq(List.wrap(name) ++ composition.aliases)
  defp aliases(_composition, name, false), do: List.wrap(name)

  defp manuscript(name, nil), do: "copy: #{name}"
  defp manuscript(name, copy_date), do: "copy: #{name}, #{copy_date}"

  @doc "A siglum's work key: '4Q174' -> 'dss_4q174', '4Q223_224' -> 'dss_4q223_224'."
  @spec work_key(String.t()) :: String.t()
  def work_key(siglum), do: "dss_" <> String.downcase(siglum)
end
