defmodule Bezalel.Data.FathersTest do
  use ExUnit.Case, async: true

  alias Bezalel.Data.{Fathers, FathersPack, Pack}

  @pin %{
    "greek" => %{
      "repo" => "https://github.com/jtauber/apostolic-fathers",
      "commit" => "g1",
      "path" => "texts"
    },
    "english" => %{"repo" => "https://github.com/jcuenod/CAFE", "commit" => "e1"}
  }

  defp lines(name, text), do: Fathers.parse(name, text)

  describe "join/2" do
    test "joins Greek and English line by line" do
      greek = lines("g", "0.1 Διδαχὴ κυρίου.\n1.1 Ὁδοὶ δύο εἰσί.\n")
      english = lines("e", "0.1 The Teaching of the Lord.\n1.1 There are two paths.")

      assert Fathers.join(greek, english) ==
               {:ok,
                [
                  {1, "0.1", "Διδαχὴ κυρίου.", "The Teaching of the Lord."},
                  {2, "1.1", "Ὁδοὶ δύο εἰσί.", "There are two paths."}
                ]}
    end

    test "names every reference only one side has, and lines out of step" do
      greek = lines("g", "1.1 α\n1.2 β\n1.3 γ")
      english = lines("e", "1.1 a\n1.3 c\n1.4 d")

      assert {:error, differences} = Fathers.join(greek, english)
      assert "1.2: Greek only" in differences
      assert "1.4: English only" in differences
      assert "Greek line 2 1.2, English line 2 1.3" in differences
    end

    test "a line that isn't '<reference> <text>' stops the build" do
      assert_raise ArgumentError, ~r/g:2: not '<reference> <text>'/, fn ->
        lines("g", "1.1 α\n1.2\n")
      end
    end
  end

  describe "classify/2" do
    test "the Shepherd is three works by book; its section titles are headings" do
      assert Fathers.classify("013-shepherd", "1.1.1") == {:passage, "hermas_visions", [1, 1, 1]}
      assert Fathers.classify("013-shepherd", "9.1.1") == {:passage, "hermas_mandates", [4, 1, 1]}

      assert Fathers.classify("013-shepherd", "26.30.3") ==
               {:passage, "hermas_similitudes", [9, 30, 3]}

      assert Fathers.classify("013-shepherd", "6.0.0") == :heading
    end

    test "the Moscow epilogue is a work of its own; subscriptions are left out" do
      assert Fathers.classify("014-martyrdom", "EP.2") ==
               {:passage, "martyrdom_of_polycarp_moscow_epilogue", [2]}

      assert Fathers.classify("014-martyrdom", "EP.0") == :heading

      assert Fathers.classify("014-martyrdom", "22.3") ==
               {:passage, "martyrdom_of_polycarp", [22, 3]}

      assert Fathers.classify("012-barnabas", "SB.1") == :subscription
      assert Fathers.classify("011-didache", "0.1") == {:passage, "didache", [0, 1]}
    end

    test "any other reference stops the build" do
      assert_raise ArgumentError, ~r/unknown reference "EP.1"/, fn ->
        Fathers.classify("011-didache", "EP.1")
      end

      assert_raise ArgumentError, ~r/book 28/, fn ->
        Fathers.classify("013-shepherd", "28.1.1")
      end

      assert_raise ArgumentError, fn -> Fathers.classify("011-didache", "1.1.1") end
    end
  end

  describe "passages/2" do
    setup do
      greek =
        Map.new(Fathers.stems(), fn stem -> {stem, {"1.1 α\n", "1.1 a\n"}} end)

      files =
        greek
        |> Map.put(
          "011-didache",
          {"0.1 Διδαχὴ.\n9.1 Περὶ δὲ τῆς εὐχαριστίας,\n",
           "0.1 Teaching.\n9.1 Now about the Thanksgiving,\n"}
        )
        |> Map.put(
          "013-shepherd",
          {"1.0.0 Ὅρασις αʹ\n1.1.1 Ὁ θρέψας με\n27.1.1 Postquam perscripseram\n",
           "1.0.0 Vision 1\n1.1.1 The man who raised me\n27.1.1 After I had written\n"}
        )
        |> Map.put(
          "012-barnabas",
          {"1.1 Χαίρετε\nSB.1 Ἐπιστολὴ Βαρνάβα.\n",
           "1.1 Greetings\nSB.1 The Letter of Barnabas.\n"}
        )
        |> Map.put(
          "014-martyrdom",
          {"1.1 Ἐγράψαμεν\nEP.0 EPILOGUS\nEP.1 Ταῦτα\n",
           "1.1 We wrote\nEP.0 Epilogue\nEP.1 These things\n"}
        )

      {rows, counts} = Fathers.passages(files, Fathers.provenance(@pin))
      %{rows: rows, counts: counts}
    end

    test "one row per verse, cited and sorted as the registry numbers it, its line linked", %{
      rows: rows
    } do
      didache = Enum.find(rows, &(&1.reference == "Didache 9.1"))

      assert %{
               work_key: "didache",
               author: "Anonymous",
               text: "Now about the Thanksgiving,",
               original_text: "Περὶ δὲ τῆς εὐχαριστίας,",
               original_language: "Greek",
               sort_start: 9001,
               sort_end: 9001,
               source_url:
                 "https://github.com/jtauber/apostolic-fathers/blob/g1/texts/011-didache.txt#L2"
             } = didache

      assert didache.translation =~ "a machine translation, GPT-4o's first drafts"
      assert didache.translation =~ "not a published human translation"

      similitude = Enum.find(rows, &(&1.work_key == "hermas_similitudes"))
      assert %{reference: "Hermas, Similitude 10.1.1", sort_start: 10_001_001} = similitude
      assert similitude.original_language == "Latin"

      assert Enum.any?(rows, &(&1.reference == "Martyrdom of Polycarp, Moscow epilogue 1"))
    end

    test "headings and subscriptions are left out and counted", %{rows: rows, counts: counts} do
      assert {"013-shepherd", "1.0.0", "Ὅρασις αʹ"} in counts.headings
      assert {"014-martyrdom", "EP.0", "EPILOGUS"} in counts.headings
      assert counts.subscriptions == [{"012-barnabas", "SB.1", "Ἐπιστολὴ Βαρνάβα."}]
      refute Enum.any?(rows, &(&1.text in ["Vision 1", "The Letter of Barnabas.", "Epilogue"]))
      assert counts.latin == 1
    end

    test "the pack is searchable with the ancient pack's columns", %{rows: rows} do
      path = Path.join(System.tmp_dir!(), "fathers-#{System.unique_integer([:positive])}.sqlite")

      try do
        :ok = FathersPack.write(path, rows, %{"licences" => "CC BY-SA 4.0"})

        assert Pack.read(
                 path,
                 "SELECT reference FROM ancient_source_passages_fts WHERE ancient_source_passages_fts MATCH ?",
                 ["original_text_folded : \"ευχαριστιασ\""]
               ) == [["Didache 9.1"]]

        assert Pack.read(path, "SELECT value FROM pack_meta WHERE key = 'pack'") == [["fathers"]]
      after
        File.rm(path)
      end
    end
  end

  test "Greek is folded for search as the ancient pack folds it" do
    assert Fathers.index_text("Ὁδοὶ δύο εἰσί, [μία] τῆς ζωῆς") == "οδοι δυο εισι, μια τησ ζωησ"
    assert Fathers.language("Quodsi de ceteris montibus") == "Latin"
    assert Fathers.language("Ὁδοὶ δύο") == "Greek"
  end
end
