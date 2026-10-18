defmodule Bezalel.Data.PackTest do
  use ExUnit.Case, async: true

  alias Bezalel.Data.{Net, Pack}

  @moduletag :tmp_dir

  test "writes the translations pack the study tools read", %{tmp_dir: dir} do
    path = Path.join(dir, "translations.sqlite")

    translation =
      Map.merge(Net.translation(), %{source_url: "https://example.org", source_sha256: "abc"})

    rows = [
      %{reference: "Psa.3.0", book: "Psa", chapter: 3, verse: 0, text: "By David."},
      %{reference: "Psa.3.1", book: "Psa", chapter: 3, verse: 1, text: "LORD, rise up!"}
    ]

    :ok = Pack.write(path, [translation], %{"net" => rows}, %{"built_by" => "test"})

    assert Pack.read(
             path,
             "SELECT reference, text FROM translation_verses WHERE translation = 'net' " <>
               "AND reference IN (?, ?) ORDER BY verse",
             ["Psa.3.0", "Psa.3.1"]
           ) == [["Psa.3.0", "By David."], ["Psa.3.1", "LORD, rise up!"]]

    assert [["net", "NET", "abc"]] =
             Pack.read(path, "SELECT key, abbreviation, source_sha256 FROM translations")

    meta = path |> Pack.read("SELECT key, value FROM pack_meta") |> Map.new(&List.to_tuple/1)

    assert %{
             "pack" => "translations",
             "tables" => "translations translation_verses",
             "built_by" => "test"
           } = meta

    assert Map.has_key?(meta, "sqlite_version")

    assert [["4096"]] = Pack.read(path, "SELECT CAST(page_size AS TEXT) FROM pragma_page_size")
  end

  test "rejects a duplicate reference", %{tmp_dir: dir} do
    row = %{reference: "Gen.1.1", book: "Gen", chapter: 1, verse: 1, text: "x"}

    assert_raise MatchError, fn ->
      Pack.write(Path.join(dir, "t.sqlite"), [], %{"net" => [row, row]}, %{})
    end
  end
end
