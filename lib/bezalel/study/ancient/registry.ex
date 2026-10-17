defmodule Bezalel.Study.Ancient.Registry do
  @moduledoc """
  studybible-mcp's registry of ancient-source corpora (`corpora/*.py` at
  the pinned commit, MIT) as data: each corpus's label, caveat, periods,
  tag, and citable works with their names, collections, tags and locator
  grammars. Generated from the Python registry (`CORPORA`); the passages
  themselves are in the ancient pack. Display order is the registry's.
  """

  # Date tiers: how much a text can testify to about the first century.
  @tiers %{
    "A" => "written before or alongside the NT",
    "B" =>
      "after the NT (to c. AD 200); first-century background only where an earlier witness agrees"
  }

  # How a curated link relates a passage to the Bible.
  @relations %{
    "aligned" => "Aligned",
    "contrast" => "Contrast",
    "echo" => "Echo",
    "shared_tradition" => "Shared tradition",
    "translation" => "Translation of"
  }

  @corpora [
    %{
      label: "Josephus",
      tag: %{
        status: "Not Scripture",
        date: "c. AD 75–100",
        kind: "Jewish history",
        edition: "Niese Greek, Whiston English",
        manuscript: nil,
        sections: [],
        tier: "A"
      },
      aliases: ["Flavius Josephus", "Josephus", "Jos."],
      key: "josephus",
      caveat:
        "Not Scripture: a Jewish historian writing c. AD 75–100; his editorial framing is his own.",
      example_citation: "Antiquities 18.116",
      heading_label: "Whiston chapter heading",
      line_numbered: false,
      no_english_note: "No English translation included",
      original_language: "Greek",
      periods: [
        "biblical",
        "persian",
        "second_temple",
        "hellenistic",
        "hasmonean",
        "herodian",
        "roman",
        "first_jewish_revolt"
      ],
      works: [
        %{
          tag: %{
            status: "Not Scripture",
            date: "AD 93–94",
            kind: "Jewish history",
            edition: "Niese Greek, Whiston English",
            manuscript: nil,
            sections: [],
            tier: "A"
          },
          title: "Jewish Antiquities",
          aliases: [
            "Ant.",
            "A.J.",
            "Antiquities of the Jews",
            "Antiquitates Judaicae",
            "Jewish Ant."
          ],
          key: "antiquities",
          collection: nil,
          coverage_note: "",
          locator: %{
            name: "book.section",
            depth: 2,
            separator: ".",
            books: 20,
            example: "1.1",
            roman: false,
            scale: 1000
          },
          reference_title: "Antiquities"
        },
        %{
          tag: %{
            status: "Not Scripture",
            date: "c. AD 94–100",
            kind: "Jewish history",
            edition: "Niese Greek, Whiston English",
            manuscript: nil,
            sections: [],
            tier: "A"
          },
          title: "Life of Josephus",
          aliases: ["Vita", "Vit.", "The Life"],
          key: "life",
          collection: nil,
          coverage_note: "",
          locator: %{
            name: "section",
            depth: 1,
            separator: ".",
            books: nil,
            example: "116",
            roman: false,
            scale: 1000
          },
          reference_title: "Life"
        },
        %{
          tag: %{
            status: "Not Scripture",
            date: "c. AD 95–100",
            kind: "Jewish history",
            edition: "Niese Greek, Whiston English",
            manuscript: nil,
            sections: [],
            tier: "A"
          },
          title: "Against Apion",
          aliases: ["C. Ap.", "Ap.", "Apion", "Ag. Ap.", "Contra Apionem"],
          key: "against_apion",
          collection: nil,
          coverage_note: "",
          locator: %{
            name: "book.section",
            depth: 2,
            separator: ".",
            books: 2,
            example: "1.1",
            roman: false,
            scale: 1000
          },
          reference_title: "Against Apion"
        },
        %{
          tag: %{
            status: "Not Scripture",
            date: "c. AD 75–79",
            kind: "Jewish history",
            edition: "Niese Greek, Whiston English",
            manuscript: nil,
            sections: [],
            tier: "A"
          },
          title: "The Jewish War",
          aliases: [
            "B.J.",
            "J.W.",
            "Jewish War",
            "Wars of the Jews",
            "War of the Jews",
            "Bellum Judaicum",
            "Bell."
          ],
          key: "jewish_war",
          collection: nil,
          coverage_note: "",
          locator: %{
            name: "book.section",
            depth: 2,
            separator: ".",
            books: 7,
            example: "1.1",
            roman: false,
            scale: 1000
          },
          reference_title: "War"
        }
      ]
    },
    %{
      label: "Targum",
      tag: %{
        status: "Not Scripture",
        date: "final form c. 3rd–5th c. AD, Babylonia",
        kind: "Jewish Aramaic Torah rendering",
        edition:
          "Torat Emet Aramaic; Metsudah: English of the Hebrew Torah; ⟨marked⟩ words are Onkelos's renderings",
        manuscript: nil,
        sections: [],
        tier: "B"
      },
      aliases: ["Targum", "Targums", "Tg."],
      key: "targum",
      caveat:
        "Not Scripture: a Jewish Aramaic rendering of the Torah (final form c. 3rd–5th c. AD) that avoids describing God bodily.",
      example_citation: "Onkelos Genesis 1:2",
      heading_label: "Editorial heading",
      line_numbered: false,
      no_english_note: "No English translation included",
      original_language: "Aramaic",
      periods: ["amoraic"],
      works: [
        %{
          tag: nil,
          title: "Genesis",
          aliases: ["Gen.", "Gn.", "Bereshit", "Bereshith", "Bereishit"],
          key: "onkelos_genesis",
          collection: %{
            title: "Targum Onkelos",
            aliases: ["Onkelos", "Onqelos", "Targum Onqelos", "Tg. Onq.", "Tg. Onk.", "Onk."]
          },
          coverage_note: "",
          locator: %{
            name: "chapter:verse",
            depth: 2,
            separator: ":",
            books: nil,
            example: "1:1",
            roman: false,
            scale: 1000
          },
          reference_title: "Genesis"
        },
        %{
          tag: nil,
          title: "Exodus",
          aliases: ["Exod.", "Exo.", "Ex.", "Shemot", "Shemoth"],
          key: "onkelos_exodus",
          collection: %{
            title: "Targum Onkelos",
            aliases: ["Onkelos", "Onqelos", "Targum Onqelos", "Tg. Onq.", "Tg. Onk.", "Onk."]
          },
          coverage_note: "",
          locator: %{
            name: "chapter:verse",
            depth: 2,
            separator: ":",
            books: nil,
            example: "1:1",
            roman: false,
            scale: 1000
          },
          reference_title: "Exodus"
        },
        %{
          tag: nil,
          title: "Leviticus",
          aliases: ["Lev.", "Lv.", "Vayikra", "Vaiyikra"],
          key: "onkelos_leviticus",
          collection: %{
            title: "Targum Onkelos",
            aliases: ["Onkelos", "Onqelos", "Targum Onqelos", "Tg. Onq.", "Tg. Onk.", "Onk."]
          },
          coverage_note: "",
          locator: %{
            name: "chapter:verse",
            depth: 2,
            separator: ":",
            books: nil,
            example: "1:1",
            roman: false,
            scale: 1000
          },
          reference_title: "Leviticus"
        },
        %{
          tag: nil,
          title: "Numbers",
          aliases: ["Num.", "Nm.", "Bamidbar", "Bemidbar"],
          key: "onkelos_numbers",
          collection: %{
            title: "Targum Onkelos",
            aliases: ["Onkelos", "Onqelos", "Targum Onqelos", "Tg. Onq.", "Tg. Onk.", "Onk."]
          },
          coverage_note: "",
          locator: %{
            name: "chapter:verse",
            depth: 2,
            separator: ":",
            books: nil,
            example: "1:1",
            roman: false,
            scale: 1000
          },
          reference_title: "Numbers"
        },
        %{
          tag: nil,
          title: "Deuteronomy",
          aliases: ["Deut.", "Dt.", "Devarim", "Debarim"],
          key: "onkelos_deuteronomy",
          collection: %{
            title: "Targum Onkelos",
            aliases: ["Onkelos", "Onqelos", "Targum Onqelos", "Tg. Onq.", "Tg. Onk.", "Onk."]
          },
          coverage_note: "",
          locator: %{
            name: "chapter:verse",
            depth: 2,
            separator: ":",
            books: nil,
            example: "1:1",
            roman: false,
            scale: 1000
          },
          reference_title: "Deuteronomy"
        }
      ]
    },
    %{
      label: "Qumran",
      tag: nil,
      aliases: ["Dead Sea Scrolls", "Qumran", "DSS"],
      key: "qumran",
      caveat:
        "Not Scripture: sectarian texts of a strict priestly movement (c. 150–50 BC). [ ] marks modern reconstruction, never evidence; any English is the assistant's own.",
      example_citation: "CD 6:11",
      heading_label: "Editorial heading",
      line_numbered: true,
      no_english_note: "No English translation included",
      original_language: "Hebrew",
      periods: ["second_temple", "hasmonean", "roman"],
      works: [
        %{
          tag: %{
            status: "Not Scripture",
            date: "composed 2nd–1st c. BC",
            kind: "Qumran sectarian rule",
            edition: "Abegg–Bowley–Cook Hebrew (ETCBC)",
            manuscript: "copies: Cairo Genizah MS A, 10th c. AD; MS B, 11th–12th c. AD",
            sections: [
              %{
                name: "",
                date: "",
                manuscript: "copy: Cairo Genizah MS A, 10th c. AD",
                tier: "",
                locator: "1-16"
              },
              %{
                name: "",
                date: "",
                manuscript: "copy: Cairo Genizah MS B, 11th–12th c. AD",
                tier: "",
                locator: "19-20"
              }
            ],
            tier: "A"
          },
          title: "Damascus Document",
          aliases: ["Damascus Rule", "Zadokite Fragments", "Zadokite Work"],
          key: "damascus_document",
          collection: nil,
          coverage_note: "",
          locator: %{
            name: "column:line",
            depth: 2,
            separator: ":",
            books: nil,
            example: "6:11",
            roman: true,
            scale: 1000
          },
          reference_title: "CD"
        },
        %{
          tag: %{
            status: "Not Scripture",
            date: "c. 100 BC; Cave 1 copy c. 75 BC",
            kind: "Qumran sectarian rule",
            edition: "Abegg–Bowley–Cook Hebrew (ETCBC)",
            manuscript: nil,
            sections: [],
            tier: "A"
          },
          title: "Community Rule",
          aliases: ["Rule of the Community", "Manual of Discipline"],
          key: "community_rule",
          collection: nil,
          coverage_note: "",
          locator: %{
            name: "column:line",
            depth: 2,
            separator: ":",
            books: nil,
            example: "6:11",
            roman: true,
            scale: 1000
          },
          reference_title: "1QS"
        },
        %{
          tag: %{
            status: "Not Scripture",
            date: "c. 100 BC; Cave 1 copy c. 75 BC",
            kind: "Qumran sectarian rule",
            edition: "Abegg–Bowley–Cook Hebrew (ETCBC)",
            manuscript: nil,
            sections: [],
            tier: "A"
          },
          title: "Rule of the Congregation",
          aliases: ["1Q28a", "Messianic Rule"],
          key: "rule_of_the_congregation",
          collection: nil,
          coverage_note: "",
          locator: %{
            name: "column:line",
            depth: 2,
            separator: ":",
            books: nil,
            example: "6:11",
            roman: true,
            scale: 1000
          },
          reference_title: "1QSa"
        },
        %{
          tag: %{
            status: "Not Scripture",
            date: "Herodian-era copy, late 1st c. BC",
            kind: "Qumran pesher",
            edition: "Abegg–Bowley–Cook Hebrew (ETCBC)",
            manuscript: nil,
            sections: [],
            tier: "A"
          },
          title: "Pesher Habakkuk",
          aliases: ["Habakkuk Pesher", "Habakkuk Commentary"],
          key: "pesher_habakkuk",
          collection: nil,
          coverage_note: "",
          locator: %{
            name: "column:line",
            depth: 2,
            separator: ":",
            books: nil,
            example: "6:11",
            roman: true,
            scale: 1000
          },
          reference_title: "1QpHab"
        }
      ]
    },
    %{
      label: "Philo",
      tag: %{
        status: "Not Scripture",
        date: "c. AD 20–50",
        kind: "Hellenistic Jewish philosophy",
        edition: "Cohn–Wendland Greek, Yonge English 1854–55",
        manuscript: nil,
        sections: [],
        tier: "A"
      },
      aliases: ["Philo of Alexandria", "Philo Judaeus", "Philo"],
      key: "philo",
      caveat:
        "Not Scripture; not Christian. Platonising allegory on the Greek Pentateuch; his Logos is not the incarnate Son (John 1:14; Heb 1).",
      example_citation: "Opif. 26",
      heading_label: "Yonge treatise heading",
      line_numbered: false,
      no_english_note: "Yonge has no English for this section",
      original_language: "Greek",
      periods: ["second_temple", "roman"],
      works: [
        %{
          tag: nil,
          title: "On the Creation of the World",
          aliases: ["Op.", "De Opificio Mundi", "On the Creation", "Creation of the World"],
          key: "opif",
          collection: nil,
          coverage_note: "",
          locator: %{
            name: "section",
            depth: 1,
            separator: ".",
            books: nil,
            example: "116",
            roman: false,
            scale: 1000
          },
          reference_title: "Opif."
        },
        %{
          tag: nil,
          title: "Allegorical Interpretation",
          aliases: [
            "Leg. All.",
            "Legum Allegoriae",
            "Allegorical Interpretation of Genesis",
            "On the Allegories of the Sacred Laws"
          ],
          key: "leg",
          collection: nil,
          coverage_note: "",
          locator: %{
            name: "book.section",
            depth: 2,
            separator: ".",
            books: 3,
            example: "1.1",
            roman: false,
            scale: 1000
          },
          reference_title: "Leg."
        },
        %{
          tag: nil,
          title: "On the Cherubim",
          aliases: ["De Cherubim"],
          key: "cher",
          collection: nil,
          coverage_note: "",
          locator: %{
            name: "section",
            depth: 1,
            separator: ".",
            books: nil,
            example: "116",
            roman: false,
            scale: 1000
          },
          reference_title: "Cher."
        },
        %{
          tag: nil,
          title: "On the Sacrifices of Abel and Cain",
          aliases: ["De Sacrificiis Abelis et Caini", "On the Sacrifice of Abel and Cain"],
          key: "sacr",
          collection: nil,
          coverage_note: "",
          locator: %{
            name: "section",
            depth: 1,
            separator: ".",
            books: nil,
            example: "116",
            roman: false,
            scale: 1000
          },
          reference_title: "Sacr."
        },
        %{
          tag: nil,
          title: "That the Worse Attacks the Better",
          aliases: ["Quod Deterius Potiori Insidiari Soleat", "Quod Deterius"],
          key: "det",
          collection: nil,
          coverage_note: "",
          locator: %{
            name: "section",
            depth: 1,
            separator: ".",
            books: nil,
            example: "116",
            roman: false,
            scale: 1000
          },
          reference_title: "Det."
        },
        %{
          tag: nil,
          title: "On the Posterity of Cain",
          aliases: ["De Posteritate Caini"],
          key: "post",
          collection: nil,
          coverage_note: "",
          locator: %{
            name: "section",
            depth: 1,
            separator: ".",
            books: nil,
            example: "116",
            roman: false,
            scale: 1000
          },
          reference_title: "Post."
        },
        %{
          tag: nil,
          title: "On the Giants",
          aliases: ["De Gigantibus"],
          key: "gig",
          collection: nil,
          coverage_note: "",
          locator: %{
            name: "section",
            depth: 1,
            separator: ".",
            books: nil,
            example: "116",
            roman: false,
            scale: 1000
          },
          reference_title: "Gig."
        },
        %{
          tag: nil,
          title: "That God Is Unchangeable",
          aliases: [
            "Immut.",
            "Quod Deus Sit Immutabilis",
            "Quod Deus",
            "On the Unchangeableness of God"
          ],
          key: "deus",
          collection: nil,
          coverage_note: "",
          locator: %{
            name: "section",
            depth: 1,
            separator: ".",
            books: nil,
            example: "116",
            roman: false,
            scale: 1000
          },
          reference_title: "Deus"
        },
        %{
          tag: nil,
          title: "On Husbandry",
          aliases: ["De Agricultura", "On Agriculture", "On the Tilling of the Earth by Noah"],
          key: "agr",
          collection: nil,
          coverage_note: "",
          locator: %{
            name: "section",
            depth: 1,
            separator: ".",
            books: nil,
            example: "116",
            roman: false,
            scale: 1000
          },
          reference_title: "Agr."
        },
        %{
          tag: nil,
          title: "On Planting",
          aliases: ["De Plantatione", "About the Planting of Noah"],
          key: "plant",
          collection: nil,
          coverage_note: "",
          locator: %{
            name: "section",
            depth: 1,
            separator: ".",
            books: nil,
            example: "116",
            roman: false,
            scale: 1000
          },
          reference_title: "Plant."
        },
        %{
          tag: nil,
          title: "On Drunkenness",
          aliases: ["De Ebrietate"],
          key: "ebr",
          collection: nil,
          coverage_note: "",
          locator: %{
            name: "section",
            depth: 1,
            separator: ".",
            books: nil,
            example: "116",
            roman: false,
            scale: 1000
          },
          reference_title: "Ebr."
        },
        %{
          tag: nil,
          title: "On Sobriety",
          aliases: ["De Sobrietate"],
          key: "sobr",
          collection: nil,
          coverage_note: "",
          locator: %{
            name: "section",
            depth: 1,
            separator: ".",
            books: nil,
            example: "116",
            roman: false,
            scale: 1000
          },
          reference_title: "Sobr."
        },
        %{
          tag: nil,
          title: "On the Confusion of Tongues",
          aliases: ["De Confusione Linguarum", "On the Confusion of Languages"],
          key: "conf",
          collection: nil,
          coverage_note: "",
          locator: %{
            name: "section",
            depth: 1,
            separator: ".",
            books: nil,
            example: "116",
            roman: false,
            scale: 1000
          },
          reference_title: "Conf."
        },
        %{
          tag: nil,
          title: "On the Migration of Abraham",
          aliases: ["De Migratione Abrahami"],
          key: "migr",
          collection: nil,
          coverage_note: "",
          locator: %{
            name: "section",
            depth: 1,
            separator: ".",
            books: nil,
            example: "116",
            roman: false,
            scale: 1000
          },
          reference_title: "Migr."
        },
        %{
          tag: nil,
          title: "Who Is the Heir of Divine Things",
          aliases: ["Heres", "Quis Rerum Divinarum Heres Sit", "Quis Heres", "Who Is the Heir"],
          key: "her",
          collection: nil,
          coverage_note: "",
          locator: %{
            name: "section",
            depth: 1,
            separator: ".",
            books: nil,
            example: "116",
            roman: false,
            scale: 1000
          },
          reference_title: "Her."
        },
        %{
          tag: nil,
          title: "On the Preliminary Studies",
          aliases: [
            "De Congressu Eruditionis Gratia",
            "De Congressu",
            "On Mating with the Preliminary Studies"
          ],
          key: "congr",
          collection: nil,
          coverage_note: "",
          locator: %{
            name: "section",
            depth: 1,
            separator: ".",
            books: nil,
            example: "116",
            roman: false,
            scale: 1000
          },
          reference_title: "Congr."
        },
        %{
          tag: nil,
          title: "On Flight and Finding",
          aliases: ["De Fuga et Inventione", "On Fugitives"],
          key: "fug",
          collection: nil,
          coverage_note: "",
          locator: %{
            name: "section",
            depth: 1,
            separator: ".",
            books: nil,
            example: "116",
            roman: false,
            scale: 1000
          },
          reference_title: "Fug."
        },
        %{
          tag: nil,
          title: "On the Change of Names",
          aliases: ["De Mutatione Nominum"],
          key: "mut",
          collection: nil,
          coverage_note: "",
          locator: %{
            name: "section",
            depth: 1,
            separator: ".",
            books: nil,
            example: "116",
            roman: false,
            scale: 1000
          },
          reference_title: "Mut."
        },
        %{
          tag: nil,
          title: "On Dreams",
          aliases: ["De Somniis"],
          key: "somn",
          collection: nil,
          coverage_note: "",
          locator: %{
            name: "book.section",
            depth: 2,
            separator: ".",
            books: 2,
            example: "1.1",
            roman: false,
            scale: 1000
          },
          reference_title: "Somn."
        },
        %{
          tag: nil,
          title: "On the Life of Abraham",
          aliases: ["De Abrahamo", "On Abraham", "Life of Abraham"],
          key: "abr",
          collection: nil,
          coverage_note: "",
          locator: %{
            name: "section",
            depth: 1,
            separator: ".",
            books: nil,
            example: "116",
            roman: false,
            scale: 1000
          },
          reference_title: "Abr."
        },
        %{
          tag: nil,
          title: "On the Life of Joseph",
          aliases: ["De Iosepho", "De Josepho", "On Joseph", "Life of Joseph"],
          key: "ios",
          collection: nil,
          coverage_note: "",
          locator: %{
            name: "section",
            depth: 1,
            separator: ".",
            books: nil,
            example: "116",
            roman: false,
            scale: 1000
          },
          reference_title: "Ios."
        },
        %{
          tag: nil,
          title: "On the Life of Moses",
          aliases: ["Vit. Mos.", "De Vita Mosis", "Life of Moses"],
          key: "mos",
          collection: nil,
          coverage_note: "",
          locator: %{
            name: "book.section",
            depth: 2,
            separator: ".",
            books: 2,
            example: "1.1",
            roman: false,
            scale: 1000
          },
          reference_title: "Mos."
        },
        %{
          tag: nil,
          title: "On the Decalogue",
          aliases: ["De Decalogo", "Concerning the Ten Commandments"],
          key: "decal",
          collection: nil,
          coverage_note: "",
          locator: %{
            name: "section",
            depth: 1,
            separator: ".",
            books: nil,
            example: "116",
            roman: false,
            scale: 1000
          },
          reference_title: "Decal."
        },
        %{
          tag: nil,
          title: "On the Special Laws",
          aliases: ["Spec. Leg.", "De Specialibus Legibus"],
          key: "spec",
          collection: nil,
          coverage_note: "",
          locator: %{
            name: "book.section",
            depth: 2,
            separator: ".",
            books: 4,
            example: "1.1",
            roman: false,
            scale: 1000
          },
          reference_title: "Spec."
        },
        %{
          tag: nil,
          title: "On the Virtues",
          aliases: ["De Virtutibus", "On Three Virtues"],
          key: "virt",
          collection: nil,
          coverage_note: "",
          locator: %{
            name: "section",
            depth: 1,
            separator: ".",
            books: nil,
            example: "116",
            roman: false,
            scale: 1000
          },
          reference_title: "Virt."
        },
        %{
          tag: nil,
          title: "On Rewards and Punishments",
          aliases: ["De Praemiis et Poenis"],
          key: "praem",
          collection: nil,
          coverage_note: "",
          locator: %{
            name: "section",
            depth: 1,
            separator: ".",
            books: nil,
            example: "116",
            roman: false,
            scale: 1000
          },
          reference_title: "Praem."
        },
        %{
          tag: nil,
          title: "That Every Good Person Is Free",
          aliases: [
            "Quod Omnis Probus Liber Sit",
            "Quod Omnis Probus",
            "That Every Good Man Is Free",
            "Every Good Man Is Free"
          ],
          key: "prob",
          collection: nil,
          coverage_note: "",
          locator: %{
            name: "section",
            depth: 1,
            separator: ".",
            books: nil,
            example: "116",
            roman: false,
            scale: 1000
          },
          reference_title: "Prob."
        },
        %{
          tag: nil,
          title: "On the Contemplative Life",
          aliases: ["Vit. Cont.", "De Vita Contemplativa", "Contemplative Life"],
          key: "contempl",
          collection: nil,
          coverage_note: "",
          locator: %{
            name: "section",
            depth: 1,
            separator: ".",
            books: nil,
            example: "116",
            roman: false,
            scale: 1000
          },
          reference_title: "Contempl."
        },
        %{
          tag: nil,
          title: "On the Eternity of the World",
          aliases: ["De Aeternitate Mundi", "On the Incorruptibility of the World"],
          key: "aet",
          collection: nil,
          coverage_note: "",
          locator: %{
            name: "section",
            depth: 1,
            separator: ".",
            books: nil,
            example: "116",
            roman: false,
            scale: 1000
          },
          reference_title: "Aet."
        },
        %{
          tag: nil,
          title: "Against Flaccus",
          aliases: ["In Flaccum"],
          key: "flacc",
          collection: nil,
          coverage_note: "",
          locator: %{
            name: "section",
            depth: 1,
            separator: ".",
            books: nil,
            example: "116",
            roman: false,
            scale: 1000
          },
          reference_title: "Flacc."
        },
        %{
          tag: nil,
          title: "On the Embassy to Gaius",
          aliases: ["Leg. Gai.", "Legatio ad Gaium", "Embassy to Gaius"],
          key: "legat",
          collection: nil,
          coverage_note: "",
          locator: %{
            name: "section",
            depth: 1,
            separator: ".",
            books: nil,
            example: "116",
            roman: false,
            scale: 1000
          },
          reference_title: "Legat."
        }
      ]
    },
    %{
      label: "Pseudepigrapha",
      tag: nil,
      aliases: [],
      key: "pseudepigrapha",
      caveat:
        "Not Scripture: pseudepigrapha outside the 66-book canon; background only, never a basis for doctrine. Jude 14–15 quotes 1 Enoch 1:9 without making the book Scripture.",
      example_citation: "1 Enoch 89:73",
      heading_label: "Charles section heading",
      line_numbered: false,
      no_english_note: "No English translation included",
      original_language: "Ge'ez",
      periods: ["second_temple", "hellenistic", "roman"],
      works: [
        %{
          tag: %{
            status: "Not Scripture",
            date: "c. 300 BC–1st c. AD",
            kind: "Jewish pseudepigraphon",
            edition: "Charles 1912",
            manuscript: nil,
            sections: [
              %{
                name: "Book of the Watchers",
                date: "4th–3rd c. BC",
                manuscript: nil,
                tier: "A",
                locator: "1-36"
              },
              %{
                name: "Parables",
                date: "c. 50 BC–AD 117, debated",
                manuscript: nil,
                tier: "A/B",
                locator: "37-71"
              },
              %{
                name: "Astronomical Book",
                date: "3rd c. BC",
                manuscript: nil,
                tier: "A",
                locator: "72-82"
              },
              %{
                name: "Dream Visions",
                date: "c. 165–160 BC",
                manuscript: nil,
                tier: "A",
                locator: "83-90"
              },
              %{
                name: "Epistle of Enoch",
                date: "2nd c. BC",
                manuscript: nil,
                tier: "A",
                locator: "91-107"
              },
              %{
                name: "appendix",
                date: "late addition, date uncertain",
                manuscript: nil,
                tier: "A/B",
                locator: "108"
              }
            ],
            tier: "A/B"
          },
          title: "1 Enoch",
          aliases: ["1 En.", "Ethiopic Enoch", "Book of Enoch", "Ethiopic Apocalypse of Enoch"],
          key: "1_enoch",
          collection: nil,
          coverage_note: "",
          locator: %{
            name: "chapter:verse",
            depth: 2,
            separator: ":",
            books: nil,
            example: "1:1",
            roman: false,
            scale: 1000
          },
          reference_title: "1 Enoch"
        },
        %{
          tag: %{
            status: "Not Scripture",
            date: "c. AD 100",
            kind: "Jewish apocalypse, 2 Esd 3–14",
            edition: "KJV 2 Esdras, Clementine Latin",
            manuscript: nil,
            sections: [],
            tier: "B"
          },
          title: "4 Ezra",
          aliases: ["4 Ezr.", "2 Esdras", "2 Esd.", "4 Esdras", "4 Esd."],
          key: "4_ezra",
          collection: nil,
          coverage_note:
            "Only 4 Ezra (2 Esdras 3–14) is served: 2 Esdras 1–2 and 15–16, the later Christian additions (5 and 6 Ezra), are excluded, and the KJV and Latin lack 4 Ezra 7:36–105 (the 'missing fragment', published by Bensly in 1875).",
          locator: %{
            name: "chapter:verse",
            depth: 2,
            separator: ":",
            books: nil,
            example: "1:1",
            roman: false,
            scale: 1000
          },
          reference_title: "4 Ezra"
        }
      ]
    },
    %{
      label: "Rabbinic",
      tag: %{
        status: "Not Scripture",
        date: "redacted c. AD 200; pre-70 attributions unverified",
        kind: "Mishnah",
        edition: "Vilna Hebrew, Kulp English",
        manuscript: nil,
        sections: [],
        tier: "B"
      },
      aliases: ["Rabbinic"],
      key: "rabbinic",
      caveat:
        "Not Scripture: rabbinic tradition redacted c. AD 200; attributions to pre-70 sages are unverified, and Kulp's bracketed Bible references sometimes use Hebrew numbering or contain errors. Where the NT evaluates these traditions (Mark 7; Matt 19; Heb 9–10), the NT's judgment governs.",
      example_citation: "Mishnah Shekalim 1:1",
      heading_label: "Editorial heading",
      line_numbered: false,
      no_english_note: "No English translation included",
      original_language: "Hebrew",
      periods: ["tannaitic"],
      works: [
        %{
          tag: nil,
          title: "Berakhot",
          aliases: ["Ber.", "Berachot", "Brachot"],
          key: "mishnah_berakhot",
          collection: %{title: "Mishnah", aliases: ["m."]},
          coverage_note: "",
          locator: %{
            name: "chapter:mishnah",
            depth: 2,
            separator: ":",
            books: nil,
            example: "1:1",
            roman: false,
            scale: 1000
          },
          reference_title: "Berakhot"
        },
        %{
          tag: nil,
          title: "Peah",
          aliases: ["Pea"],
          key: "mishnah_peah",
          collection: %{title: "Mishnah", aliases: ["m."]},
          coverage_note: "",
          locator: %{
            name: "chapter:mishnah",
            depth: 2,
            separator: ":",
            books: nil,
            example: "1:1",
            roman: false,
            scale: 1000
          },
          reference_title: "Peah"
        },
        %{
          tag: nil,
          title: "Demai",
          aliases: ["Dem."],
          key: "mishnah_demai",
          collection: %{title: "Mishnah", aliases: ["m."]},
          coverage_note: "",
          locator: %{
            name: "chapter:mishnah",
            depth: 2,
            separator: ":",
            books: nil,
            example: "1:1",
            roman: false,
            scale: 1000
          },
          reference_title: "Demai"
        },
        %{
          tag: nil,
          title: "Kilayim",
          aliases: ["Kil.", "Kilaim"],
          key: "mishnah_kilayim",
          collection: %{title: "Mishnah", aliases: ["m."]},
          coverage_note: "",
          locator: %{
            name: "chapter:mishnah",
            depth: 2,
            separator: ":",
            books: nil,
            example: "1:1",
            roman: false,
            scale: 1000
          },
          reference_title: "Kilayim"
        },
        %{
          tag: nil,
          title: "Sheviit",
          aliases: ["Sheb.", "Shebiit"],
          key: "mishnah_sheviit",
          collection: %{title: "Mishnah", aliases: ["m."]},
          coverage_note: "",
          locator: %{
            name: "chapter:mishnah",
            depth: 2,
            separator: ":",
            books: nil,
            example: "1:1",
            roman: false,
            scale: 1000
          },
          reference_title: "Sheviit"
        },
        %{
          tag: nil,
          title: "Terumot",
          aliases: ["Ter.", "Terumoth"],
          key: "mishnah_terumot",
          collection: %{title: "Mishnah", aliases: ["m."]},
          coverage_note: "",
          locator: %{
            name: "chapter:mishnah",
            depth: 2,
            separator: ":",
            books: nil,
            example: "1:1",
            roman: false,
            scale: 1000
          },
          reference_title: "Terumot"
        },
        %{
          tag: nil,
          title: "Maasrot",
          aliases: ["Maas.", "Maaserot"],
          key: "mishnah_maasrot",
          collection: %{title: "Mishnah", aliases: ["m."]},
          coverage_note: "",
          locator: %{
            name: "chapter:mishnah",
            depth: 2,
            separator: ":",
            books: nil,
            example: "1:1",
            roman: false,
            scale: 1000
          },
          reference_title: "Maasrot"
        },
        %{
          tag: nil,
          title: "Maaser Sheni",
          aliases: ["Maas. Sh.", "Maaser Sheini"],
          key: "mishnah_maaser_sheni",
          collection: %{title: "Mishnah", aliases: ["m."]},
          coverage_note: "",
          locator: %{
            name: "chapter:mishnah",
            depth: 2,
            separator: ":",
            books: nil,
            example: "1:1",
            roman: false,
            scale: 1000
          },
          reference_title: "Maaser Sheni"
        },
        %{
          tag: nil,
          title: "Challah",
          aliases: ["Hal.", "Hallah"],
          key: "mishnah_challah",
          collection: %{title: "Mishnah", aliases: ["m."]},
          coverage_note: "",
          locator: %{
            name: "chapter:mishnah",
            depth: 2,
            separator: ":",
            books: nil,
            example: "1:1",
            roman: false,
            scale: 1000
          },
          reference_title: "Challah"
        },
        %{
          tag: nil,
          title: "Orlah",
          aliases: ["Orl."],
          key: "mishnah_orlah",
          collection: %{title: "Mishnah", aliases: ["m."]},
          coverage_note: "",
          locator: %{
            name: "chapter:mishnah",
            depth: 2,
            separator: ":",
            books: nil,
            example: "1:1",
            roman: false,
            scale: 1000
          },
          reference_title: "Orlah"
        },
        %{
          tag: nil,
          title: "Bikkurim",
          aliases: ["Bik.", "Bikk."],
          key: "mishnah_bikkurim",
          collection: %{title: "Mishnah", aliases: ["m."]},
          coverage_note: "",
          locator: %{
            name: "chapter:mishnah",
            depth: 2,
            separator: ":",
            books: nil,
            example: "1:1",
            roman: false,
            scale: 1000
          },
          reference_title: "Bikkurim"
        },
        %{
          tag: nil,
          title: "Shabbat",
          aliases: ["Shabb.", "Shab.", "Sabbath"],
          key: "mishnah_shabbat",
          collection: %{title: "Mishnah", aliases: ["m."]},
          coverage_note: "",
          locator: %{
            name: "chapter:mishnah",
            depth: 2,
            separator: ":",
            books: nil,
            example: "1:1",
            roman: false,
            scale: 1000
          },
          reference_title: "Shabbat"
        },
        %{
          tag: nil,
          title: "Eruvin",
          aliases: ["Erub.", "Eruv.", "Erubin"],
          key: "mishnah_eruvin",
          collection: %{title: "Mishnah", aliases: ["m."]},
          coverage_note: "",
          locator: %{
            name: "chapter:mishnah",
            depth: 2,
            separator: ":",
            books: nil,
            example: "1:1",
            roman: false,
            scale: 1000
          },
          reference_title: "Eruvin"
        },
        %{
          tag: nil,
          title: "Pesachim",
          aliases: ["Pes.", "Pesah.", "Pesahim"],
          key: "mishnah_pesachim",
          collection: %{title: "Mishnah", aliases: ["m."]},
          coverage_note: "",
          locator: %{
            name: "chapter:mishnah",
            depth: 2,
            separator: ":",
            books: nil,
            example: "1:1",
            roman: false,
            scale: 1000
          },
          reference_title: "Pesachim"
        },
        %{
          tag: nil,
          title: "Shekalim",
          aliases: ["Shek.", "Sheqal.", "Sheqalim"],
          key: "mishnah_shekalim",
          collection: %{title: "Mishnah", aliases: ["m."]},
          coverage_note: "",
          locator: %{
            name: "chapter:mishnah",
            depth: 2,
            separator: ":",
            books: nil,
            example: "1:1",
            roman: false,
            scale: 1000
          },
          reference_title: "Shekalim"
        },
        %{
          tag: nil,
          title: "Yoma",
          aliases: ["Kippurim"],
          key: "mishnah_yoma",
          collection: %{title: "Mishnah", aliases: ["m."]},
          coverage_note: "",
          locator: %{
            name: "chapter:mishnah",
            depth: 2,
            separator: ":",
            books: nil,
            example: "1:1",
            roman: false,
            scale: 1000
          },
          reference_title: "Yoma"
        },
        %{
          tag: nil,
          title: "Sukkah",
          aliases: ["Suk.", "Sukk."],
          key: "mishnah_sukkah",
          collection: %{title: "Mishnah", aliases: ["m."]},
          coverage_note: "",
          locator: %{
            name: "chapter:mishnah",
            depth: 2,
            separator: ":",
            books: nil,
            example: "1:1",
            roman: false,
            scale: 1000
          },
          reference_title: "Sukkah"
        },
        %{
          tag: nil,
          title: "Beitzah",
          aliases: ["Besah", "Betzah", "Yom Tov"],
          key: "mishnah_beitzah",
          collection: %{title: "Mishnah", aliases: ["m."]},
          coverage_note: "",
          locator: %{
            name: "chapter:mishnah",
            depth: 2,
            separator: ":",
            books: nil,
            example: "1:1",
            roman: false,
            scale: 1000
          },
          reference_title: "Beitzah"
        },
        %{
          tag: nil,
          title: "Rosh Hashanah",
          aliases: ["RH", "Rosh Hash."],
          key: "mishnah_rosh_hashanah",
          collection: %{title: "Mishnah", aliases: ["m."]},
          coverage_note: "",
          locator: %{
            name: "chapter:mishnah",
            depth: 2,
            separator: ":",
            books: nil,
            example: "1:1",
            roman: false,
            scale: 1000
          },
          reference_title: "Rosh Hashanah"
        },
        %{
          tag: nil,
          title: "Taanit",
          aliases: ["Taan.", "Taanith"],
          key: "mishnah_taanit",
          collection: %{title: "Mishnah", aliases: ["m."]},
          coverage_note: "",
          locator: %{
            name: "chapter:mishnah",
            depth: 2,
            separator: ":",
            books: nil,
            example: "1:1",
            roman: false,
            scale: 1000
          },
          reference_title: "Taanit"
        },
        %{
          tag: nil,
          title: "Megillah",
          aliases: ["Meg."],
          key: "mishnah_megillah",
          collection: %{title: "Mishnah", aliases: ["m."]},
          coverage_note: "",
          locator: %{
            name: "chapter:mishnah",
            depth: 2,
            separator: ":",
            books: nil,
            example: "1:1",
            roman: false,
            scale: 1000
          },
          reference_title: "Megillah"
        },
        %{
          tag: nil,
          title: "Moed Katan",
          aliases: ["MK", "Moed Qat.", "Moed Qatan"],
          key: "mishnah_moed_katan",
          collection: %{title: "Mishnah", aliases: ["m."]},
          coverage_note: "",
          locator: %{
            name: "chapter:mishnah",
            depth: 2,
            separator: ":",
            books: nil,
            example: "1:1",
            roman: false,
            scale: 1000
          },
          reference_title: "Moed Katan"
        },
        %{
          tag: nil,
          title: "Chagigah",
          aliases: ["Hag.", "Hagigah"],
          key: "mishnah_chagigah",
          collection: %{title: "Mishnah", aliases: ["m."]},
          coverage_note: "",
          locator: %{
            name: "chapter:mishnah",
            depth: 2,
            separator: ":",
            books: nil,
            example: "1:1",
            roman: false,
            scale: 1000
          },
          reference_title: "Chagigah"
        },
        %{
          tag: nil,
          title: "Yevamot",
          aliases: ["Yev.", "Yebam.", "Yebamot"],
          key: "mishnah_yevamot",
          collection: %{title: "Mishnah", aliases: ["m."]},
          coverage_note: "",
          locator: %{
            name: "chapter:mishnah",
            depth: 2,
            separator: ":",
            books: nil,
            example: "1:1",
            roman: false,
            scale: 1000
          },
          reference_title: "Yevamot"
        },
        %{
          tag: nil,
          title: "Ketubot",
          aliases: ["Ket.", "Ketub.", "Ketuboth"],
          key: "mishnah_ketubot",
          collection: %{title: "Mishnah", aliases: ["m."]},
          coverage_note: "",
          locator: %{
            name: "chapter:mishnah",
            depth: 2,
            separator: ":",
            books: nil,
            example: "1:1",
            roman: false,
            scale: 1000
          },
          reference_title: "Ketubot"
        },
        %{
          tag: nil,
          title: "Nedarim",
          aliases: ["Ned."],
          key: "mishnah_nedarim",
          collection: %{title: "Mishnah", aliases: ["m."]},
          coverage_note: "",
          locator: %{
            name: "chapter:mishnah",
            depth: 2,
            separator: ":",
            books: nil,
            example: "1:1",
            roman: false,
            scale: 1000
          },
          reference_title: "Nedarim"
        },
        %{
          tag: nil,
          title: "Nazir",
          aliases: ["Naz."],
          key: "mishnah_nazir",
          collection: %{title: "Mishnah", aliases: ["m."]},
          coverage_note: "",
          locator: %{
            name: "chapter:mishnah",
            depth: 2,
            separator: ":",
            books: nil,
            example: "1:1",
            roman: false,
            scale: 1000
          },
          reference_title: "Nazir"
        },
        %{
          tag: nil,
          title: "Sotah",
          aliases: ["Sot.", "Sota"],
          key: "mishnah_sotah",
          collection: %{title: "Mishnah", aliases: ["m."]},
          coverage_note: "",
          locator: %{
            name: "chapter:mishnah",
            depth: 2,
            separator: ":",
            books: nil,
            example: "1:1",
            roman: false,
            scale: 1000
          },
          reference_title: "Sotah"
        },
        %{
          tag: nil,
          title: "Gittin",
          aliases: ["Git."],
          key: "mishnah_gittin",
          collection: %{title: "Mishnah", aliases: ["m."]},
          coverage_note: "",
          locator: %{
            name: "chapter:mishnah",
            depth: 2,
            separator: ":",
            books: nil,
            example: "1:1",
            roman: false,
            scale: 1000
          },
          reference_title: "Gittin"
        },
        %{
          tag: nil,
          title: "Kiddushin",
          aliases: ["Kid.", "Qidd.", "Qiddushin"],
          key: "mishnah_kiddushin",
          collection: %{title: "Mishnah", aliases: ["m."]},
          coverage_note: "",
          locator: %{
            name: "chapter:mishnah",
            depth: 2,
            separator: ":",
            books: nil,
            example: "1:1",
            roman: false,
            scale: 1000
          },
          reference_title: "Kiddushin"
        },
        %{
          tag: nil,
          title: "Bava Kamma",
          aliases: ["BK", "B. Qam.", "Baba Kamma", "Bava Qamma"],
          key: "mishnah_bava_kamma",
          collection: %{title: "Mishnah", aliases: ["m."]},
          coverage_note: "",
          locator: %{
            name: "chapter:mishnah",
            depth: 2,
            separator: ":",
            books: nil,
            example: "1:1",
            roman: false,
            scale: 1000
          },
          reference_title: "Bava Kamma"
        },
        %{
          tag: nil,
          title: "Bava Metzia",
          aliases: ["BM", "B. Mes.", "Baba Metzia", "Baba Mezia"],
          key: "mishnah_bava_metzia",
          collection: %{title: "Mishnah", aliases: ["m."]},
          coverage_note: "",
          locator: %{
            name: "chapter:mishnah",
            depth: 2,
            separator: ":",
            books: nil,
            example: "1:1",
            roman: false,
            scale: 1000
          },
          reference_title: "Bava Metzia"
        },
        %{
          tag: nil,
          title: "Bava Batra",
          aliases: ["BB", "B. Bat.", "Baba Bathra", "Baba Batra"],
          key: "mishnah_bava_batra",
          collection: %{title: "Mishnah", aliases: ["m."]},
          coverage_note: "",
          locator: %{
            name: "chapter:mishnah",
            depth: 2,
            separator: ":",
            books: nil,
            example: "1:1",
            roman: false,
            scale: 1000
          },
          reference_title: "Bava Batra"
        },
        %{
          tag: nil,
          title: "Sanhedrin",
          aliases: ["Sanh."],
          key: "mishnah_sanhedrin",
          collection: %{title: "Mishnah", aliases: ["m."]},
          coverage_note: "",
          locator: %{
            name: "chapter:mishnah",
            depth: 2,
            separator: ":",
            books: nil,
            example: "1:1",
            roman: false,
            scale: 1000
          },
          reference_title: "Sanhedrin"
        },
        %{
          tag: nil,
          title: "Makkot",
          aliases: ["Mak.", "Makkoth"],
          key: "mishnah_makkot",
          collection: %{title: "Mishnah", aliases: ["m."]},
          coverage_note: "",
          locator: %{
            name: "chapter:mishnah",
            depth: 2,
            separator: ":",
            books: nil,
            example: "1:1",
            roman: false,
            scale: 1000
          },
          reference_title: "Makkot"
        },
        %{
          tag: nil,
          title: "Shevuot",
          aliases: ["Shebu.", "Shevu.", "Shebuot"],
          key: "mishnah_shevuot",
          collection: %{title: "Mishnah", aliases: ["m."]},
          coverage_note: "",
          locator: %{
            name: "chapter:mishnah",
            depth: 2,
            separator: ":",
            books: nil,
            example: "1:1",
            roman: false,
            scale: 1000
          },
          reference_title: "Shevuot"
        },
        %{
          tag: nil,
          title: "Eduyot",
          aliases: ["Ed.", "Eduy.", "Eduyyot"],
          key: "mishnah_eduyot",
          collection: %{title: "Mishnah", aliases: ["m."]},
          coverage_note: "",
          locator: %{
            name: "chapter:mishnah",
            depth: 2,
            separator: ":",
            books: nil,
            example: "1:1",
            roman: false,
            scale: 1000
          },
          reference_title: "Eduyot"
        },
        %{
          tag: nil,
          title: "Avodah Zarah",
          aliases: ["AZ", "Abod. Zar.", "Avod. Zar.", "Avoda Zara"],
          key: "mishnah_avodah_zarah",
          collection: %{title: "Mishnah", aliases: ["m."]},
          coverage_note: "",
          locator: %{
            name: "chapter:mishnah",
            depth: 2,
            separator: ":",
            books: nil,
            example: "1:1",
            roman: false,
            scale: 1000
          },
          reference_title: "Avodah Zarah"
        },
        %{
          tag: nil,
          title: "Pirkei Avot",
          aliases: ["Avot", "Abot", "Aboth", "Pirke Avot"],
          key: "mishnah_pirkei_avot",
          collection: %{title: "Mishnah", aliases: ["m."]},
          coverage_note: "",
          locator: %{
            name: "chapter:mishnah",
            depth: 2,
            separator: ":",
            books: nil,
            example: "1:1",
            roman: false,
            scale: 1000
          },
          reference_title: "Pirkei Avot"
        },
        %{
          tag: nil,
          title: "Horayot",
          aliases: ["Hor."],
          key: "mishnah_horayot",
          collection: %{title: "Mishnah", aliases: ["m."]},
          coverage_note: "",
          locator: %{
            name: "chapter:mishnah",
            depth: 2,
            separator: ":",
            books: nil,
            example: "1:1",
            roman: false,
            scale: 1000
          },
          reference_title: "Horayot"
        },
        %{
          tag: nil,
          title: "Zevachim",
          aliases: ["Zev.", "Zebah.", "Zebahim", "Zevahim"],
          key: "mishnah_zevachim",
          collection: %{title: "Mishnah", aliases: ["m."]},
          coverage_note: "",
          locator: %{
            name: "chapter:mishnah",
            depth: 2,
            separator: ":",
            books: nil,
            example: "1:1",
            roman: false,
            scale: 1000
          },
          reference_title: "Zevachim"
        },
        %{
          tag: nil,
          title: "Menachot",
          aliases: ["Men.", "Menah.", "Menahot"],
          key: "mishnah_menachot",
          collection: %{title: "Mishnah", aliases: ["m."]},
          coverage_note: "",
          locator: %{
            name: "chapter:mishnah",
            depth: 2,
            separator: ":",
            books: nil,
            example: "1:1",
            roman: false,
            scale: 1000
          },
          reference_title: "Menachot"
        },
        %{
          tag: nil,
          title: "Chullin",
          aliases: ["Hul.", "Hullin"],
          key: "mishnah_chullin",
          collection: %{title: "Mishnah", aliases: ["m."]},
          coverage_note: "",
          locator: %{
            name: "chapter:mishnah",
            depth: 2,
            separator: ":",
            books: nil,
            example: "1:1",
            roman: false,
            scale: 1000
          },
          reference_title: "Chullin"
        },
        %{
          tag: nil,
          title: "Bekhorot",
          aliases: ["Bek.", "Bekh.", "Bekorot"],
          key: "mishnah_bekhorot",
          collection: %{title: "Mishnah", aliases: ["m."]},
          coverage_note: "",
          locator: %{
            name: "chapter:mishnah",
            depth: 2,
            separator: ":",
            books: nil,
            example: "1:1",
            roman: false,
            scale: 1000
          },
          reference_title: "Bekhorot"
        },
        %{
          tag: nil,
          title: "Arakhin",
          aliases: ["Arak.", "Arakin"],
          key: "mishnah_arakhin",
          collection: %{title: "Mishnah", aliases: ["m."]},
          coverage_note: "",
          locator: %{
            name: "chapter:mishnah",
            depth: 2,
            separator: ":",
            books: nil,
            example: "1:1",
            roman: false,
            scale: 1000
          },
          reference_title: "Arakhin"
        },
        %{
          tag: nil,
          title: "Temurah",
          aliases: ["Tem."],
          key: "mishnah_temurah",
          collection: %{title: "Mishnah", aliases: ["m."]},
          coverage_note: "",
          locator: %{
            name: "chapter:mishnah",
            depth: 2,
            separator: ":",
            books: nil,
            example: "1:1",
            roman: false,
            scale: 1000
          },
          reference_title: "Temurah"
        },
        %{
          tag: nil,
          title: "Keritot",
          aliases: ["Ker.", "Kerithot"],
          key: "mishnah_keritot",
          collection: %{title: "Mishnah", aliases: ["m."]},
          coverage_note: "",
          locator: %{
            name: "chapter:mishnah",
            depth: 2,
            separator: ":",
            books: nil,
            example: "1:1",
            roman: false,
            scale: 1000
          },
          reference_title: "Keritot"
        },
        %{
          tag: nil,
          title: "Meilah",
          aliases: ["Meil."],
          key: "mishnah_meilah",
          collection: %{title: "Mishnah", aliases: ["m."]},
          coverage_note: "",
          locator: %{
            name: "chapter:mishnah",
            depth: 2,
            separator: ":",
            books: nil,
            example: "1:1",
            roman: false,
            scale: 1000
          },
          reference_title: "Meilah"
        },
        %{
          tag: nil,
          title: "Tamid",
          aliases: ["Tam."],
          key: "mishnah_tamid",
          collection: %{title: "Mishnah", aliases: ["m."]},
          coverage_note: "",
          locator: %{
            name: "chapter:mishnah",
            depth: 2,
            separator: ":",
            books: nil,
            example: "1:1",
            roman: false,
            scale: 1000
          },
          reference_title: "Tamid"
        },
        %{
          tag: nil,
          title: "Middot",
          aliases: ["Mid.", "Midd."],
          key: "mishnah_middot",
          collection: %{title: "Mishnah", aliases: ["m."]},
          coverage_note: "",
          locator: %{
            name: "chapter:mishnah",
            depth: 2,
            separator: ":",
            books: nil,
            example: "1:1",
            roman: false,
            scale: 1000
          },
          reference_title: "Middot"
        },
        %{
          tag: nil,
          title: "Kinnim",
          aliases: ["Qin.", "Qinnim"],
          key: "mishnah_kinnim",
          collection: %{title: "Mishnah", aliases: ["m."]},
          coverage_note: "",
          locator: %{
            name: "chapter:mishnah",
            depth: 2,
            separator: ":",
            books: nil,
            example: "1:1",
            roman: false,
            scale: 1000
          },
          reference_title: "Kinnim"
        },
        %{
          tag: nil,
          title: "Kelim",
          aliases: ["Kel."],
          key: "mishnah_kelim",
          collection: %{title: "Mishnah", aliases: ["m."]},
          coverage_note: "",
          locator: %{
            name: "chapter:mishnah",
            depth: 2,
            separator: ":",
            books: nil,
            example: "1:1",
            roman: false,
            scale: 1000
          },
          reference_title: "Kelim"
        },
        %{
          tag: nil,
          title: "Oholot",
          aliases: ["Ohal.", "Ohol.", "Ohalot", "Ahilot"],
          key: "mishnah_oholot",
          collection: %{title: "Mishnah", aliases: ["m."]},
          coverage_note: "",
          locator: %{
            name: "chapter:mishnah",
            depth: 2,
            separator: ":",
            books: nil,
            example: "1:1",
            roman: false,
            scale: 1000
          },
          reference_title: "Oholot"
        },
        %{
          tag: nil,
          title: "Negaim",
          aliases: ["Neg."],
          key: "mishnah_negaim",
          collection: %{title: "Mishnah", aliases: ["m."]},
          coverage_note: "",
          locator: %{
            name: "chapter:mishnah",
            depth: 2,
            separator: ":",
            books: nil,
            example: "1:1",
            roman: false,
            scale: 1000
          },
          reference_title: "Negaim"
        },
        %{
          tag: nil,
          title: "Parah",
          aliases: ["Par."],
          key: "mishnah_parah",
          collection: %{title: "Mishnah", aliases: ["m."]},
          coverage_note: "",
          locator: %{
            name: "chapter:mishnah",
            depth: 2,
            separator: ":",
            books: nil,
            example: "1:1",
            roman: false,
            scale: 1000
          },
          reference_title: "Parah"
        },
        %{
          tag: nil,
          title: "Tahorot",
          aliases: ["Tehar.", "Toh.", "Tohorot", "Teharot"],
          key: "mishnah_tahorot",
          collection: %{title: "Mishnah", aliases: ["m."]},
          coverage_note: "",
          locator: %{
            name: "chapter:mishnah",
            depth: 2,
            separator: ":",
            books: nil,
            example: "1:1",
            roman: false,
            scale: 1000
          },
          reference_title: "Tahorot"
        },
        %{
          tag: nil,
          title: "Mikvaot",
          aliases: ["Mikv.", "Miqw.", "Miqvaot"],
          key: "mishnah_mikvaot",
          collection: %{title: "Mishnah", aliases: ["m."]},
          coverage_note: "",
          locator: %{
            name: "chapter:mishnah",
            depth: 2,
            separator: ":",
            books: nil,
            example: "1:1",
            roman: false,
            scale: 1000
          },
          reference_title: "Mikvaot"
        },
        %{
          tag: nil,
          title: "Niddah",
          aliases: ["Nid.", "Nidd."],
          key: "mishnah_niddah",
          collection: %{title: "Mishnah", aliases: ["m."]},
          coverage_note: "",
          locator: %{
            name: "chapter:mishnah",
            depth: 2,
            separator: ":",
            books: nil,
            example: "1:1",
            roman: false,
            scale: 1000
          },
          reference_title: "Niddah"
        },
        %{
          tag: nil,
          title: "Makhshirin",
          aliases: ["Maksh.", "Makhsh.", "Makshirin"],
          key: "mishnah_makhshirin",
          collection: %{title: "Mishnah", aliases: ["m."]},
          coverage_note: "",
          locator: %{
            name: "chapter:mishnah",
            depth: 2,
            separator: ":",
            books: nil,
            example: "1:1",
            roman: false,
            scale: 1000
          },
          reference_title: "Makhshirin"
        },
        %{
          tag: nil,
          title: "Zavim",
          aliases: ["Zab.", "Zabim"],
          key: "mishnah_zavim",
          collection: %{title: "Mishnah", aliases: ["m."]},
          coverage_note: "",
          locator: %{
            name: "chapter:mishnah",
            depth: 2,
            separator: ":",
            books: nil,
            example: "1:1",
            roman: false,
            scale: 1000
          },
          reference_title: "Zavim"
        },
        %{
          tag: nil,
          title: "Tevul Yom",
          aliases: ["T. Yom", "Tebul Yom"],
          key: "mishnah_tevul_yom",
          collection: %{title: "Mishnah", aliases: ["m."]},
          coverage_note: "",
          locator: %{
            name: "chapter:mishnah",
            depth: 2,
            separator: ":",
            books: nil,
            example: "1:1",
            roman: false,
            scale: 1000
          },
          reference_title: "Tevul Yom"
        },
        %{
          tag: nil,
          title: "Yadayim",
          aliases: ["Yad."],
          key: "mishnah_yadayim",
          collection: %{title: "Mishnah", aliases: ["m."]},
          coverage_note: "",
          locator: %{
            name: "chapter:mishnah",
            depth: 2,
            separator: ":",
            books: nil,
            example: "1:1",
            roman: false,
            scale: 1000
          },
          reference_title: "Yadayim"
        },
        %{
          tag: nil,
          title: "Oktzin",
          aliases: ["Uq.", "Uktzin", "Uqsin", "Oktsin"],
          key: "mishnah_oktzin",
          collection: %{title: "Mishnah", aliases: ["m."]},
          coverage_note: "",
          locator: %{
            name: "chapter:mishnah",
            depth: 2,
            separator: ":",
            books: nil,
            example: "1:1",
            roman: false,
            scale: 1000
          },
          reference_title: "Oktzin"
        }
      ]
    }
  ]

  @doc "Every corpus, in registry order."
  def corpora, do: @corpora

  @doc "The tier key to its description."
  def tiers, do: @tiers

  @doc "A link relation key to its label."
  def relations, do: @relations
end
