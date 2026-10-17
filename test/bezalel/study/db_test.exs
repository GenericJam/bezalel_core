defmodule Bezalel.Study.DBTest do
  # Changes the packs directory, so not async.
  use ExUnit.Case, async: false

  alias Bezalel.Study.{DB, Tools}

  setup do
    fixtures = Application.fetch_env!(:bezalel_core, :packs_dir)
    dir = Path.join(System.tmp_dir!(), "bezalel-packs-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)

    on_exit(fn ->
      Application.put_env(:bezalel_core, :packs_dir, fixtures)
      File.rm_rf!(dir)
    end)

    %{fixtures: fixtures, dir: dir}
  end

  test "a tool whose pack isn't downloaded says which pack, and the others still work",
       %{fixtures: fixtures, dir: dir} do
    File.ln_s!(Path.join(fixtures, "core.sqlite"), Path.join(dir, "core.sqlite"))
    Application.put_env(:bezalel_core, :packs_dir, dir)

    assert DB.available?(:core)
    refute DB.available?(:graph)

    assert {:error, message} =
             Tools.PeopleInPassage.run(%{"reference" => "Exodus 31"}, %{})

    assert message =~ "The graph study pack (people, places and events) isn't downloaded"
    assert {:ok, _} = Tools.LookupVerse.run(%{"reference" => "Exodus 31:3"}, %{})
  end

  test "a pack that isn't a database is an error, not a crash", %{dir: dir} do
    File.write!(Path.join(dir, "core.sqlite"), "not a database")
    Application.put_env(:bezalel_core, :packs_dir, dir)

    assert {:error, "The core study pack on this device can't be read" <> _} =
             Tools.WordStudy.run(%{"strongs" => "H7307"}, %{})
  end

  test "the packs directory can be a function the host app resolves at run time", %{dir: dir} do
    Application.put_env(:bezalel_core, :packs_dir, {Path, :join, [dir, "packs"]})

    assert DB.dir() == Path.join(dir, "packs")
    assert DB.path(:core) == Path.join([dir, "packs", "core.sqlite"])
  end

  test "an app that hasn't named the packs directory gets an error saying so" do
    Application.delete_env(:bezalel_core, :packs_dir)

    assert_raise ArgumentError, ~r/config :bezalel_core, :packs_dir is not set/, fn ->
      DB.dir()
    end
  end

  test "packs are opened read-only" do
    assert {:ok, {:error, message}} =
             DB.with_pack(:core, &Exqlite.Sqlite3.execute(&1, "DELETE FROM lexicon"))

    assert message =~ "readonly"
  end

  test "tools run in parallel, each on its own connection" do
    calls =
      for _ <- 1..8,
          call <- [
            {Tools.LookupVerse, %{"reference" => "Exodus 31"}},
            {Tools.WordStudy, %{"strongs" => "H7307"}},
            {Tools.GetCrossReferences, %{"reference" => "John 3:16"}},
            {Tools.PeopleInPassage, %{"reference" => "Exodus 31"}}
          ],
          do: call

    expected =
      Map.new(Enum.uniq(calls), fn {tool, args} -> {{tool, args}, tool.run(args, %{})} end)

    results =
      calls
      |> Task.async_stream(fn {tool, args} -> {{tool, args}, tool.run(args, %{})} end,
        max_concurrency: 8
      )
      |> Enum.map(fn {:ok, result} -> result end)

    for {call, result} <- results, do: assert(result == expected[call])
  end
end
