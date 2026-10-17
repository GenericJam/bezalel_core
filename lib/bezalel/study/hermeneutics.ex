defmodule Bezalel.Study.Hermeneutics do
  @moduledoc """
  Genre-aware reading guidance, after Fee & Stuart's "How to Read the Bible
  for All Its Worth": each book's genre, and for each genre its key
  principle, approach, common errors and application questions.
  `lookup_verse` appends the passage's genre guidance; the system prompt
  (`Bezalel.Study.Prompt`) summarises the genres.

  Ported from studybible-mcp's `hermeneutics.py` (MIT), text unchanged.
  """

  alias Bezalel.Study.{Patterns, Reference}

  @book_genres %{
    "Gen" => "ot_narrative",
    "Exo" => "ot_narrative",
    "Num" => "ot_narrative",
    "Jos" => "ot_narrative",
    "Jdg" => "ot_narrative",
    "Rut" => "ot_narrative",
    "1Sa" => "ot_narrative",
    "2Sa" => "ot_narrative",
    "1Ki" => "ot_narrative",
    "2Ki" => "ot_narrative",
    "1Ch" => "ot_narrative",
    "2Ch" => "ot_narrative",
    "Ezr" => "ot_narrative",
    "Neh" => "ot_narrative",
    "Est" => "ot_narrative",
    "Jon" => "ot_narrative",
    "Lev" => "law",
    "Deu" => "law",
    "Job" => "wisdom",
    "Pro" => "wisdom",
    "Ecc" => "wisdom",
    "Sng" => "wisdom",
    "Psa" => "psalm",
    "Isa" => "prophet",
    "Jer" => "prophet",
    "Lam" => "prophet",
    "Ezk" => "prophet",
    "Dan" => "prophet",
    "Hos" => "prophet",
    "Jol" => "prophet",
    "Amo" => "prophet",
    "Oba" => "prophet",
    "Mic" => "prophet",
    "Nam" => "prophet",
    "Hab" => "prophet",
    "Zep" => "prophet",
    "Hag" => "prophet",
    "Zec" => "prophet",
    "Mal" => "prophet",
    "Mat" => "gospel",
    "Mrk" => "gospel",
    "Luk" => "gospel",
    "Jhn" => "gospel",
    "Act" => "acts",
    "Rom" => "epistle",
    "1Co" => "epistle",
    "2Co" => "epistle",
    "Gal" => "epistle",
    "Eph" => "epistle",
    "Php" => "epistle",
    "Col" => "epistle",
    "1Th" => "epistle",
    "2Th" => "epistle",
    "1Ti" => "epistle",
    "2Ti" => "epistle",
    "Tit" => "epistle",
    "Phm" => "epistle",
    "Heb" => "epistle",
    "Jas" => "epistle",
    "1Pe" => "epistle",
    "2Pe" => "epistle",
    "1Jn" => "epistle",
    "2Jn" => "epistle",
    "3Jn" => "epistle",
    "Jud" => "epistle",
    "Rev" => "apocalyptic"
  }

  # In studybible-mcp's order (the order the prompt's genre table uses).
  @guidelines [
    {"epistle",
     %{
       name: "Epistles (Letters)",
       key_principle: "Think contextually - what problem was being addressed?",
       approach: [
         "Identify the occasion: What problem or situation prompted this letter?",
         "Understand the relationship between author and recipients",
         "Read the whole letter at once to grasp the argument flow",
         "Pay attention to logical connectors (therefore, because, so that)",
         "Distinguish between the central argument and supporting points"
       ],
       common_errors: [
         "Taking verses out of their argumentative context",
         "Ignoring the historical situation being addressed",
         "Treating every statement as universally prescriptive",
         "Missing the logical flow by reading only isolated passages"
       ],
       application_questions: [
         "Is this addressing a specific first-century issue or a timeless principle?",
         "Does the broader biblical witness inform this teaching?",
         "Is the instruction tied to creation order or cultural context?"
       ]
     }},
    {"ot_narrative",
     %{
       name: "Old Testament Narratives",
       key_principle:
         "Three levels of narrative (meta, national, individual); descriptive not prescriptive",
       approach: [
         "Remember: narratives describe what happened, not necessarily what should happen",
         "Look for the three levels: God's universal plan, Israel's story, individual accounts",
         "Characters are not always examples to follow - observe their flaws",
         "The narrator rarely makes direct theological statements",
         "God is the ultimate hero of every narrative"
       ],
       common_errors: [
         "Treating every character's action as a model to follow",
         "Allegorizing details that are simply historical facts",
         "Missing the larger redemptive-historical purpose",
         "Moralizing: 'Be brave like David' without seeing God's work"
       ],
       application_questions: [
         "What does this reveal about God's character and purposes?",
         "How does this fit into the larger story of redemption?",
         "Is this action approved, disapproved, or simply recorded?"
       ]
     }},
    {"acts",
     %{
       name: "Acts (Historical Narrative)",
       key_principle:
         "Historical precedent vs normative teaching - not everything repeated is required",
       approach: [
         "Acts is theological history - Luke is making a point",
         "Distinguish between what the church DID and what we MUST do",
         "Look for patterns repeated multiple times as potentially normative",
         "Unique events may not be meant as patterns for all time",
         "Read alongside the Epistles for doctrinal understanding"
       ],
       common_errors: [
         "Requiring every practice in Acts for churches today",
         "Taking unique events (Pentecost) as repeatable patterns",
         "Missing the transitional nature of this period",
         "Ignoring Luke's theological agenda in selecting what to report"
       ],
       application_questions: [
         "Is this event presented as a pattern or as a unique occurrence?",
         "Does the rest of the NT confirm this as normative?",
         "What was Luke's purpose in including this account?"
       ]
     }},
    {"gospel",
     %{
       name: "Gospels",
       key_principle: "Two-level documents (Jesus' original context + evangelist's purpose)",
       approach: [
         "Consider both Jesus' original meaning and the Gospel writer's purpose",
         "Each Gospel has a specific audience and theological emphasis",
         "Context in Jesus' ministry: Who is he speaking to?",
         "How does this teaching function in the Gospel's overall narrative?",
         "Compare parallel accounts to see each writer's emphasis"
       ],
       common_errors: [
         "Harmonizing too quickly without hearing each Gospel's voice",
         "Ignoring Jesus' audience (Pharisees, disciples, crowds)",
         "Missing the already/not-yet tension of the Kingdom",
         "Applying everything directly without considering the cross"
       ],
       application_questions: [
         "Who was Jesus addressing and what was their situation?",
         "How does the cross and resurrection affect this teaching?",
         "What does this tell us about Jesus and his Kingdom?"
       ]
     }},
    {"parable",
     %{
       name: "Parables",
       key_principle: "Find the main point; don't allegorize every detail",
       approach: [
         "Identify the one or two main points - parables are not allegories",
         "Consider the audience: Who is Jesus speaking to and why?",
         "Look for cultural background that illuminates meaning",
         "The unexpected twist often carries the main message",
         "Let the context determine the interpretation"
       ],
       common_errors: [
         "Allegorizing every detail (the donkey represents X...)",
         "Missing the shock value for the original audience",
         "Ignoring the immediate context of why Jesus told this",
         "Creating theological systems from parabolic details"
       ],
       application_questions: [
         "What is the one main point Jesus is making?",
         "What would have surprised or challenged the original hearers?",
         "How does this teach us about the Kingdom of God?"
       ]
     }},
    {"law",
     %{
       name: "Law (Torah)",
       key_principle: "Covenant stipulations; distinguish civil/ritual/ethical categories",
       approach: [
         "The Law is Israel's covenant document, not a universal law code",
         "Distinguish: Apodictic (absolute) vs. Case law (situational)",
         "Categories: Civil (Israel's government), Ritual (worship), Ethical (moral)",
         "The Law reveals God's character even when specific commands don't apply",
         "Christ fulfills the Law - consider its purpose in light of the gospel"
       ],
       common_errors: [
         "Applying Israel's civil laws directly to modern nations",
         "Ignoring the ritual laws entirely instead of finding their purpose",
         "Cherry-picking laws without consistent hermeneutic",
         "Moralizing without seeing the redemptive purpose"
       ],
       application_questions: [
         "What does this reveal about God's character and values?",
         "How is this fulfilled or transformed in Christ?",
         "What principle stands behind this specific regulation?"
       ]
     }},
    {"prophet",
     %{
       name: "Prophets",
       key_principle: "Covenant enforcement; check if 'future' is now past",
       approach: [
         "Prophets were covenant enforcement officers - calling Israel back",
         "Most 'predictions' were about events now in our past",
         "The prophetic lawsuit: accusation, judgment, hope",
         "Distinguish near fulfillment from ultimate/eschatological fulfillment",
         "Poetry and metaphor are the normal mode of prophetic speech"
       ],
       common_errors: [
         "Reading all prophecy as about the end times",
         "Literalizing poetic and metaphorical language",
         "Ignoring the historical context of the original prophecy",
         "Creating detailed end-times timelines from prophetic poetry"
       ],
       application_questions: [
         "What covenant violation was being addressed?",
         "Has this prophecy been fulfilled, or does it await fulfillment?",
         "What does this reveal about God's character and purposes?"
       ]
     }},
    {"psalm",
     %{
       name: "Psalms",
       key_principle: "Poetry/prayer; understand the types (lament, thanksgiving, praise)",
       approach: [
         "Psalms are inspired responses to God - poetry, not doctrine",
         "Identify the type: Lament, Thanksgiving, Praise, Royal, Wisdom, etc.",
         "Poetry uses metaphor, hyperbole, and parallelism",
         "The emotions are real and God-given - even the difficult ones",
         "Many psalms find their ultimate fulfillment in Christ"
       ],
       common_errors: [
         "Treating poetic expressions as doctrinal statements",
         "Ignoring the emotional dimension of the psalms",
         "Literalizing metaphorical language",
         "Skipping the imprecatory psalms or sanitizing them"
       ],
       application_questions: [
         "What type of psalm is this and what is its function?",
         "What honest emotion is being expressed to God?",
         "How does this psalm find fulfillment in Christ?"
       ]
     }},
    {"wisdom",
     %{
       name: "Wisdom Literature",
       key_principle: "General truths, not guarantees; compare with full canon",
       approach: [
         "Proverbs are general truths, not absolute promises",
         "Wisdom literature wrestles with life's complexity",
         "Job and Ecclesiastes challenge simplistic interpretations",
         "The fear of the Lord is the foundation of all wisdom",
         "Compare individual proverbs with the full biblical witness"
       ],
       common_errors: [
         "Treating Proverbs as unconditional promises (e.g., child-training)",
         "Ignoring the dialogue format in Job (not all speeches are true)",
         "Missing the 'under the sun' perspective in Ecclesiastes",
         "Applying isolated proverbs without considering counter-proverbs"
       ],
       application_questions: [
         "Is this a general principle or being stated as an absolute?",
         "How does the rest of Scripture nuance this teaching?",
         "What does this reveal about living skillfully before God?"
       ]
     }},
    {"apocalyptic",
     %{
       name: "Revelation/Apocalyptic",
       key_principle: "Apocalyptic imagery; already/not yet eschatology",
       approach: [
         "Apocalyptic is a literary genre with its own conventions",
         "Symbols are stock imagery (beasts, numbers) with recognized meanings",
         "The primary message is: God wins, evil is judged, Christ reigns",
         "Read in light of OT prophets and the already/not yet tension",
         "Multiple valid interpretive approaches exist (preterist, futurist, idealist)"
       ],
       common_errors: [
         "Literalizing symbolic imagery (666 as a barcode, locusts as helicopters)",
         "Creating detailed chronological timelines",
         "Ignoring the first-century context and audience",
         "Missing the pastoral purpose: encouragement for suffering believers"
       ],
       application_questions: [
         "What comfort or challenge did this offer the original readers?",
         "What does this reveal about God's sovereignty and Christ's victory?",
         "Am I interpreting symbols consistently with OT usage?"
       ]
     }}
  ]
  @guideline_map Map.new(@guidelines)

  @typedoc ~S'A genre key: "epistle", "ot_narrative", "gospel", …'
  @type genre :: String.t()

  @doc "The genre of a book code ('Rom'), or nil."
  @spec genre(String.t()) :: genre() | nil
  def genre(book), do: Map.get(@book_genres, book)

  @doc """
  The genre of a reference in the packs' form ('Jhn.3.16') or written out
  ('John 3:16', '1 Corinthians 13:4'); nil when it can't tell.
  """
  @spec genre_from_reference(String.t()) :: genre() | nil
  def genre_from_reference(reference) do
    case Regex.run(Patterns.get(:genre_code), reference) do
      [_, code] ->
        genre(code)

      nil ->
        case Regex.run(Patterns.get(:genre_name), String.trim(reference)) do
          [_, name] -> name |> Reference.book_code() |> then(&(&1 && genre(&1)))
          nil -> nil
        end
    end
  end

  @doc "Every genre's guidelines, in order: `[{genre, guidelines}]`."
  @spec guidelines() :: [{genre(), map()}]
  def guidelines, do: @guidelines

  @doc "The guidance for `genre` as the Markdown `lookup_verse` appends."
  @spec format_guidance(genre()) :: String.t()
  def format_guidance(genre) do
    case Map.fetch(@guideline_map, genre) do
      {:ok, g} ->
        Enum.join(
          [
            "## Genre: #{g.name}",
            "",
            "**Key Principle**: #{g.key_principle}",
            "",
            "### Interpretive Approach:"
            | bullets(g.approach)
          ] ++
            ["", "### Common Errors to Avoid:" | bullets(g.common_errors)] ++
            ["", "### Questions for Application:" | bullets(g.application_questions)],
          "\n"
        )

      :error ->
        ""
    end
  end

  defp bullets(items), do: Enum.map(items, &"- #{&1}")
end
