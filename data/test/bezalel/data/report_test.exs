defmodule Bezalel.Data.ReportTest do
  use ExUnit.Case, async: true

  alias Bezalel.Data.Report

  test "sorts references canonically, numbers as numbers" do
    assert Report.sort(["Rev.1.1", "Gen.10.1", "Gen.2.10", "Gen.2.9", "Psa.3.0"]) ==
             ["Gen.2.9", "Gen.2.10", "Gen.10.1", "Psa.3.0", "Rev.1.1"]
  end

  test "compares two verse sets" do
    assert Report.compare(["Gen.1.1", "2Co.13.13"], ["Gen.1.1", "2Co.13.13", "2Co.13.14"]) ==
             %{both: 2, only_a: [], only_b: ["2Co.13.14"]}
  end

  test "the report names what was dropped and what NET lacks" do
    report =
      Report.net(%{
        rows: [%{reference: "Psa.3.0", text: "By David."}, %{reference: "Psa.3.1", text: "LORD!"}],
        empty: ["Act.24.7"],
        headings: [{"Sng.1.2", "sosspeaker", "The Beloved:"}],
        source: "Source: test",
        bsb: {"core", ["Psa.3.0", "Psa.3.1", "Psa.3.2"]}
      })

    assert report =~ "Rows: 2 (1 Psalm superscriptions as verse 0)"
    assert report =~ "Rows with LORD (small capitals in the source): 1"
    assert report =~ "Verses the source gives without text: 1\n  Act.24.7"
    assert report =~ "sosspeaker: 1\n    Sng.1.2: The Beloved:"

    assert report =~
             "Only in the BSB (a NET lookup finds nothing): 1 (0 superscriptions)\n  Psa.3.2"
  end
end
