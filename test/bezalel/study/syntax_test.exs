defmodule Bezalel.Study.SyntaxTest do
  # The syntax pack (test/fixtures/packs/syntax.sqlite, cut by data/'s
  # `mix bezalel.data.fixtures --pack syntax`: Gen 1:1, Ps 3:0 and 22:0,
  # John 1:1 and 3:16, Eph 1:7) through lookup_verse, and lookup_verse
  # without it. Not async: the missing-pack tests repoint :packs_dir.
  use ExUnit.Case, async: false

  alias Bezalel.Study.{Citation, Preferences, Syntax}
  alias Bezalel.Study.Tools.LookupVerse

  @bsb Preferences.new(translation: "bsb", excluded_sources: ["editorial:verdicts"])

  defp result(reference, args \\ %{}) do
    {:ok, result} = LookupVerse.result(Map.put(args, "reference", reference), @bsb)
    result
  end

  defp lookup(reference, args \\ %{}), do: reference |> result(args) |> LookupVerse.render()

  # The fixture packs with the syntax pack replaced by `syntax` (nil: none),
  # for the duration of `fun`.
  defp with_syntax_pack(syntax, fun) do
    fixtures = Application.fetch_env!(:bezalel_core, :packs_dir)
    dir = Path.join(System.tmp_dir!(), "bezalel-syntax-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)

    for file <- File.ls!(fixtures),
        file != "syntax.sqlite",
        do: File.cp!(Path.join(fixtures, file), Path.join(dir, file))

    if syntax, do: File.write!(Path.join(dir, "syntax.sqlite"), syntax)
    Application.put_env(:bezalel_core, :packs_dir, dir)

    try do
      fun.()
    after
      Application.put_env(:bezalel_core, :packs_dir, fixtures)
      File.rm_rf!(dir)
    end
  end

  describe "a single verse" do
    test "Genesis 1:1 shows its clauses' parts with roles in plain English, on the WLC, cited" do
      text = lookup("Genesis 1:1")

      assert [_, section] = String.split(text, "### Clause structure\n")
      assert section =~ "Westminster Leningrad Codex (WLC), whose wording can differ"

      assert section =~ "#### Genesis 1:1\n1. Clause (PP-V-S-O): [prepositional phrase] "
      assert section =~ ~r"· \[verb\] \S+ 'created' · \[subject\] \S+ 'God' · \[object\] "

      assert section =~
               ~r"Source: \[Genesis 1:1 \(MACULA Hebrew, WLC\)\]\(https://github\.com/Clear-Bible/macula-hebrew/blob/\w{40}/WLC/lowfat/01-Gen-001-lowfat\.xml\)"

      assert [%{edition: "WLC", reference: "Gen.1.1"}] = result("Genesis 1:1").syntax
    end

    test "John 1:1: the joined clauses, each indented under them, on the SBLGNT" do
      section = Syntax.render(Syntax.verses("Jhn", [{1, 1}]))

      assert section =~ "SBL Greek New Testament (SBLGNT)"

      assert section =~
               "1. Joined clauses (Conj3CL): (clause 2) καὶ 'and' (clause 3) καὶ 'and' (clause 4)"

      assert section =~
               "\n  2. Clause (P-VC-S): [predicate] Ἐν ἀρχῇ 'In [the] beginning' · " <>
                 "[linking verb] ἦν 'was' · [subject] ὁ λόγος, 'the Word'"

      assert section =~ "\n  4. Clause (P-VC-S): [predicate] θεὸς 'God'"
    end

    test "a Psalm superscription is the WLC's verse 1, mapped to verse 0" do
      assert [%{reference: "Psa.3.0", source_reference: "Psa.3.1"}] =
               Syntax.verses("Psa", [{3, 0}])

      assert Syntax.render(Syntax.verses("Psa", [{3, 0}])) =~ "*WLC numbers this verse 3:1.*"

      text = lookup("Psalm 22:0")
      assert text =~ "*WLC numbers this verse 22:1.*"
      assert text =~ "[subject] מִזְמ֥וֹר 'psalm'"
    end

    test "a sentence running past the verse is marked, its clauses outside the verse counted" do
      text = lookup("Ephesians 1:7")

      assert text =~
               "*The sentence runs 1:7–10; its words outside this verse are in ⟨ ⟩, " <>
                 "and 5 of its clauses outside it are left out.*"

      assert text =~ "[verb] ἔχομεν 'we have'"
      assert text =~ "(a clause in 1:8–10)"
    end

    test "a verse the pack lacks has no section" do
      refute lookup("Genesis 1:3") =~ "Clause structure"
      assert result("Genesis 1:3").syntax == []
    end
  end

  describe "a passage" do
    test "has no clause structure unless include_morphology is set" do
      refute lookup("Genesis 1:1-5") =~ "Clause structure"
      assert result("Genesis 1:1-5").syntax == []
    end

    test "with include_morphology, each verse the pack has under its heading" do
      text = lookup("Genesis 1:1-2", %{"include_morphology" => true})

      assert [_, section] = String.split(text, "### Clause structure\n")
      assert section =~ "#### Genesis 1:1\n1. Clause (PP-V-S-O)"
      refute section =~ "Genesis 1:2"

      citations = LookupVerse.citations(result("Genesis 1:1-2", %{"include_morphology" => true}))

      assert [%Citation{work: "macula", locator: "Gen.1.1"}] =
               Enum.filter(citations, &(&1.work == "macula"))
    end
  end

  describe "the section's length" do
    test "is cut at whole lines, with a note saying how many were left out" do
      clause = [0, nil, "V-S", [["v", [[String.duplicate("א", 300), "H0001", "x", "א"]]]]]

      verse = %{
        reference: "Gen.1.1",
        book: "Gen",
        chapter: 1,
        verse: 1,
        edition: "WLC",
        language: "Hebrew",
        source_reference: "Gen.1.1",
        source_files: ["WLC/lowfat/01-Gen-001-lowfat.xml"],
        repo: "https://github.com/Clear-Bible/macula-hebrew",
        commit: String.duplicate("a", 40),
        sentences: [%{"c" => List.duplicate(clause, 30)}]
      }

      text = Syntax.render([verse])
      shown = text |> String.split("\n") |> Enum.count(&String.contains?(&1, "Clause (V-S)"))

      assert shown in 1..13
      assert text =~ "*Cut to keep this short: #{30 - shown} more lines not shown;"
      assert String.length(text) < 5000
    end
  end

  describe "without the pack" do
    test "lookup_verse is unchanged: no section, no MACULA source, no error" do
      with_pack = result("Genesis 1:1")
      section = Syntax.render(with_pack.syntax)
      assert section != ""

      with_syntax_pack(nil, fn ->
        without = result("Genesis 1:1")
        assert without.syntax == []

        assert LookupVerse.render(without) ==
                 String.replace(LookupVerse.render(with_pack), section, "")

        refute Enum.any?(LookupVerse.citations(without), &(&1.work == "macula"))
      end)
    end

    test "a damaged pack is left out the same way" do
      with_syntax_pack("not a database", fn ->
        assert result("Genesis 1:1").syntax == []
        refute lookup("Genesis 1:1") =~ "Clause structure"
      end)
    end
  end
end
