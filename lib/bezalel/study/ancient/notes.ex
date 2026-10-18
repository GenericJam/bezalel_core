defmodule Bezalel.Study.Ancient.Notes do
  @moduledoc """
  The editorial ⚠ notes on ancient passages (`ancient_source_notes`, written
  by studybible-mcp's maintainer), as the user's preferences allow them.

  Every one of the pack's 46 distinct notes (83 rows, one per passage) was
  read and sorted, sentence by sentence, into:

    * provenance (interpolations, emendations, restorations, editions,
      translation errors, what a passage says): always shown;
    * canon statements ("Jubilees … is not Scripture"): shown only with
      scripture labels on, and reworded to say which tradition's canon;
    * verdicts (setting a passage against the New Testament or a doctrine:
      "Christ, raised, dies no more", "compatible with, not taught by,
      Scripture"): shown only with the `editorial:verdicts` source, credited
      "Verdict (studybible-mcp):".

  A note's `contrast` field (the New Testament passages it is set against)
  is a verdict too. A note is found by the CRC-32 of its text, so a note
  this table doesn't know (a rebuilt pack) is shown as it stands, except
  that a note of kind "contrast" is then left out without the verdicts.
  """

  alias Bezalel.Study.{Preferences, Sources}

  # crc32(note) => {provenance, canon statement, verdict}. The comment is
  # the first row's id and citation in the pinned pack.
  @curated %{
    # 2, Targum Onkelos Deuteronomy 21:23 (contrast)
    449_589_514 =>
      {~S|Onkelos replaces "a hanged man is cursed by God" with "because he sinned before the LORD he was crucified" (אִצְטְלַב, root צלב). Rabbinic halakha, not anti-Christian polemic.|,
       nil, ~S|Paul says Christ became a curse "for us".|},
    # 3, Targum Onkelos Genesis 6:2–4 (contrast)
    3_701_439_069 =>
      {~S|The Aramaic turns "sons of God" into "sons of the great ones" (בְּנֵי רַבְרְבַיָּא), and Metsudah's English of the Hebrew reads "sons of the rulers": both drop the angels.|,
       nil, "The NT speaks of angels who sinned."},
    # 10, CD 16:2–4 (caution)
    2_377_312_659 =>
      {~S|Lines 3–4 name "the book of the divisions of the times into their jubilees and their weeks" (Jubilees, with its 364-day calendar) as the exact authority on Israel's times.|,
       "Jubilees is Scripture in the Ethiopian and Eritrean Orthodox Tewahedo canons and for Beta Israel; it is not in other canons.",
       nil},
    # 13, 1QS 9:11 (contrast)
    4_162_204_335 =>
      {~S|Line 11: the first ordinances bind "until the coming of a prophet and the messiahs of Aaron and Israel" (plural).|,
       nil, ~S|Hebrews has one priest-king from Judah, "not after the order of Aaron".|},
    # 17, 1QpHab 8:1–3 (contrast)
    2_415_547_796 =>
      {~S|Lines 1–3 apply Hab 2:4b to "the doers of the Torah in the house of Judah", saved for "their toil and their faith" (or fidelity) "in the Teacher of Righteousness".|,
       nil, "Paul uses it to set faith apart from works of the law."},
    # 18, 1QS 1:9–11 (contrast)
    2_651_043_973 =>
      {~S|Lines 9–11: members are "to love all the sons of light… and to hate all the sons of darkness". 10:17–20 renounces repaying evil and leaves judgment to God (cf. Rom 12:19), awaiting "the day of vengeance".|,
       nil, nil},
    # 19, CD 11:13–17 (contrast)
    1_770_005_960 =>
      {"Lines 13–14: an animal that falls into a cistern or pit is not to be lifted out on the Sabbath; 16–17: a person fallen into water is not to be brought up with a ladder, rope or utensil.",
       nil, "Jesus treats rescue as right."},
    # 20, 1QSa 2:3–9 (contrast)
    3_399_396_423 =>
      {~S|Lines 3–9 bar from the assembly anyone lame, blind, deaf, dumb, crippled in hands or feet, or blemished, "for holy angels" are in their [congregation] (line 9 partly restored).|,
       nil, "Jesus invites the crippled, lame and blind."},
    # 21, CD 6:19 (contrast)
    601_554_837 =>
      {~S|Line 19: "those who entered the new covenant in the land of Damascus" (cf. 19:33–34; 20:12), the sect's claim to Jeremiah's new covenant.|,
       nil, ~S|Jesus speaks of "the new covenant in my blood"; Hebrews applies Jer 31 to Christ.|},
    # 22, CD 20:12 (contrast)
    2_250_382_299 =>
      {~S|Line 12: "the covenant and pact they established in the land of Damascus, that is the new covenant", the sect's claim to Jeremiah's new covenant.|,
       nil, ~S|Jesus speaks of "the new covenant in my blood".|},
    # 23, Conf. 146 (contrast)
    3_828_689_536 =>
      {~S|Philo calls the Word God's "first-born", "the eldest of his angels" and "archangel".|,
       nil,
       "Shared vocabulary, different doctrine: Hebrews sets the Son above the angels, and the Word who is God became flesh."},
    # 24, Her. 206 (contrast)
    497_257_831 =>
      {~S|Philo's Word is "neither being uncreate as God, nor yet created as you" but between the two.|,
       nil,
       "John allows no middle category: the Word is God, and all things were made through him."},
    # 25, Somn. 1.229–230 (contrast)
    3_160_719_037 =>
      {~S|Philo says the article-less "God" of the Bethel text (Gen 31:13 LXX) means God's "most ancient word", called God only loosely.|,
       nil, ~S|Not a precedent for "a god" in John 1:1c: the NT calls the Son God.|},
    # 28, Gig. 6–18 (contrast)
    50_074_903 =>
      {~S|Philo's LXX reads "angels of God" (Gen 6:2), but he holds angels, demons and souls "one and identical" and makes the "angels" wicked men pursuing pleasures.|,
       nil, "The NT speaks of angels who sinned."},
    # 42, 1 Enoch 10:8 (contrast)
    3_054_444_245 =>
      {~S|"To him ascribe all sin" makes Azazel the source of all sin; 1 Enoch's own 98:4 says "man of himself has created it".|,
       nil, "Scripture traces sin's entry to Adam and its root to human desire."},
    # 43, 1 Enoch 69:9–11 (contrast)
    2_655_967_894 =>
      {~S|The angel Penemue teaches writing, and death takes hold of men "through this their knowledge".|,
       nil, "Scripture says death entered through Adam's sin, and God himself commands writing."},
    # 46, 1 Enoch 15:8–12 (caution)
    2_981_232_619 =>
      {"Evil spirits as the spirits of the giants: a Second Temple explanation of demons, adopted by Heiser.",
       nil,
       "Scripture names the Nephilim but is silent on where demons come from: compatible with, not taught by, Scripture."},
    # 51, 1 Enoch 82:4–6 (contrast)
    1_690_133_643 =>
      {~S|Blesses those who "sin not as the sinners" in reckoning a 364-day year, and faults those who miscount.|,
       nil, "The NT does not let believers be judged by their calendar."},
    # 54, 4 Ezra 7:28–29 (interpolation)
    202_647_589 =>
      {~S|"My son Jesus… my son Christ" is a Latin Christian scribal change; the Syriac, Arabic, Ethiopic and Armenian read "Messiah". This Messiah dies with all flesh after 400 years.|,
       nil, "Christ, raised, dies no more."},
    # 59, 4 Ezra 8:33 (contrast)
    3_460_866_976 =>
      {~S|"The just, which have many good works laid up with thee, shall out of their own deeds receive reward."|,
       nil, "Paul: a person is justified by faith apart from works of the law."},
    # 61, 4 Ezra 14:44–47 (contrast)
    116_374_593 =>
      {~S|The KJV/Latin "two hundred and four" books is 94 in other versions: 24 made public (the Hebrew Bible's count) and 70 kept secret as the "fountain of wisdom".|,
       nil, "Scripture presents itself as sufficient."},
    # 65, Mishnah Yoma 8:8–9 (contrast)
    3_293_629_600 =>
      {~S|Death and Yom Kippur atone "together with repentance"; for graver sins repentance suspends punishment until Yom Kippur.|,
       nil, "Hebrews: animal blood cannot take away sins, and Christ was offered once."},
    # 67, Mishnah Sanhedrin 6:2 (contrast)
    1_884_927_596 =>
      {~S|The condemned man confesses, or says "may my death be an expiation for all my sins".|,
       nil, "Hebrews grounds atonement in Christ's single offering to bear the sins of many."},
    # 69, Mishnah Sanhedrin 10:1 (contrast)
    2_428_748_545 =>
      {"Grounds a share in the world to come in belonging to Israel, minus listed exclusions, and holds that the Torah teaches resurrection.",
       nil, "The NT grounds the share in Christ, not descent."},
    # 71, Mishnah Sanhedrin 11:3 (contrast)
    699_602_054 =>
      {~S|"Greater stringency" for the scribes' teachings than for the Torah: an elder who adds to scribal rulings is liable, one who denies a Torah command exempt.|,
       nil, "Jesus faults setting aside God's command for tradition."},
    # 72, Mishnah Pirkei Avot 1:1 (contrast)
    4_167_827_222 =>
      {~S|A chain of transmission from Sinai through the elders, ending "make a fence round the Torah". The Hebrew says "Torah", not "Oral Torah".|,
       nil, "Jesus rejects the elders' tradition where it voids God's word."}
  }

  # The notes read and found to be provenance only, shown as they stand
  # (first row id, citation): 1 Antiquities 18.63–64; 6 Onkelos Genesis
  # 32:30; 7 Onkelos Deuteronomy 32:8; 8 Onkelos Exodus 23:21; 9 CD
  # 2:17–19; 11 CD 14:19; 12 CD 15:15–17; 14 1QS 8:13–14; 15 1QSa 2:11–12;
  # 16 1QpHab 7:17; 27 Mos. 2.134; 41 1 Enoch 71:14; 56 4 Ezra 7:35–106; 58
  # 4 Ezra 7:107; 60 4 Ezra 13:3; 68 Mishnah Sanhedrin 6:2; 70 Mishnah
  # Sanhedrin 10:1; 73 Mishnah Pirkei Avot 3:6; 74 Mishnah Pesachim 10; 83
  # Mishnah Pesachim 10:4.
  @provenance MapSet.new([
                2_324_636_669,
                872_701_065,
                3_292_140_369,
                3_220_073_201,
                3_834_810_286,
                3_512_516_576,
                502_944_283,
                1_446_679_774,
                2_630_017_935,
                640_781_112,
                1_795_531_854,
                2_923_348_474,
                1_137_242_735,
                2_029_883_999,
                2_750_148_109,
                4_036_407_724,
                569_519_299,
                1_305_190_853,
                2_939_472_261,
                5_885_898
              ])

  @doc "Was the note `text` read and sorted (curated or found to be provenance only)?"
  @spec audited?(String.t()) :: boolean()
  def audited?(text) do
    crc = :erlang.crc32(text)
    is_map_key(@curated, crc) or MapSet.member?(@provenance, crc)
  end

  @doc """
  A note row (`"citation"`, `"kind"`, `"note"`, `"contrast"`, `"aligned"`)
  as `prefs` allow it: the provenance, then the canon statement (scripture
  labels on) and the verdict (editorial verdicts on); the `"contrast"` field
  only with the verdicts. nil when nothing of it is left.
  """
  @spec shown(map(), Preferences.t()) :: map() | nil
  def shown(note, prefs) do
    verdicts = Sources.enabled?(prefs, "editorial:verdicts")
    fields = ~w(citation kind note aligned) ++ if(verdicts, do: ["contrast"], else: [])
    kept = Map.take(note, fields)

    case Map.fetch(@curated, :erlang.crc32(note["note"] || "")) do
      {:ok, parts} -> %{kept | "note" => curated(parts, prefs.scripture_labels, verdicts)}
      :error -> if note["kind"] == "contrast" and not verdicts, do: nil, else: kept
    end
  end

  defp curated({text, canon, verdict}, labels, verdicts) do
    [text, labels && canon, verdicts && verdict && "Verdict (studybible-mcp): #{verdict}"]
    |> Enum.filter(&is_binary/1)
    |> Enum.join(" ")
  end
end
