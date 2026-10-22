defmodule Bezalel.Data.Publish do
  @moduledoc """
  Assembles the pack manifest the apps read
  (https://bezalel.genericjam.com/packs/manifest.json, schema 1; the phone
  app parses it with `Bezalel.Packs.Manifest`) from:

  - the frozen base (`base.json`): the five packs studybible-mcp's pipeline
    built, published once as data version 1 and never uploaded again. Their
    entries keep the v1 URLs and checksums, so an app that has them sees
    the same `raw_sha256` and downloads nothing;
  - the published manifest, for the base packs' descriptions, licences,
    `required` and tables;
  - the packs built here (`translations`, `scrolls`, `fathers`, `dictionaries`, `syntax`,
    `witnesses`), uploaded under
    `packs/v<N>/`.

  Everything here is pure; `mix bezalel.data.publish` does the network.
  """

  @public_base "https://bezalel.genericjam.com"
  @sources "https://github.com/GenericJam/bezalel_mob/blob/master/data/SOURCES.md"
  @core_repo "https://github.com/GenericJam/bezalel_core"

  @top_keys ~w(schema data_version built bezalel_commit bezalel_core studybible_mcp sources packs)
  @entry_keys ~w(name description required licence url compression size sha256 raw_size raw_sha256 tables)
  @checked ~w(url size sha256 raw_size raw_sha256)

  @built_here %{
    "translations" => %{
      "description" =>
        "English Bible translations: the NET Bible, the JPS 1917 (Old Testament), and the " <>
          "Literal and Simplified Texts (ULT, UST, adapted)",
      "licence" =>
        "NET Bible® copyright ©1996, 2019 Biblical Studies Press, L.L.C.: " <>
          "free non-commercial use by permission (netbible.com/copyright); JPS 1917: public " <>
          "domain; Literal and Simplified Texts (ULT, UST, adapted): CC BY-SA 4.0 " <>
          "(https://creativecommons.org/licenses/by-sa/4.0/), the original work by " <>
          "unfoldingWord is available from unfoldingword.org/ult and unfoldingword.org/ust"
    },
    "scrolls" => %{
      "description" =>
        "Dead Sea Scrolls: major non-biblical works and the biblical manuscripts' readings " <>
          "(Hebrew and Aramaic)",
      "licence" =>
        "ETCBC/dss (Martin G. Abegg Jr., James E. Bowley, Edward M. Cook): CC BY-NC 4.0 " <>
          "(non-commercial; https://creativecommons.org/licenses/by-nc/4.0/)"
    },
    "fathers" => %{
      "description" =>
        "The Apostolic Fathers: Greek (and Latin) with a machine-translated English (CAFE)",
      "licence" =>
        "Open Apostolic Fathers (James Tauber, Seumas Macdonald; Lake's text corrected) and " <>
          "CAFE (James Cuénod; machine translation): CC BY-SA 4.0 " <>
          "(https://creativecommons.org/licenses/by-sa/4.0/)"
    },
    "dictionaries" => %{
      "description" =>
        "UBS dictionaries: Biblical Hebrew (from SDBH) and Greek New Testament (from " <>
          "Louw & Nida) meanings with semantic domains",
      "licence" =>
        "UBS Dictionary of Biblical Hebrew and UBS Dictionary of the Greek New Testament " <>
          "© United Bible Societies: CC BY-SA 4.0 (https://creativecommons.org/licenses/by-sa/4.0/)"
    },
    "syntax" => %{
      "description" =>
        "Clause structure: each verse's clauses, roles and words (MACULA syntax trees of the " <>
          "WLC and the SBLGNT)",
      "licence" =>
        "MACULA Hebrew and Greek Linguistic Datasets © 2022-2024 Biblica, Inc: CC BY 4.0 " <>
          "(https://creativecommons.org/licenses/by/4.0/); WLC text public domain, SBLGNT CC BY 4.0"
    },
    "witnesses" => %{
      "description" =>
        "Textual witnesses: the Samaritan Pentateuch, the SBL Greek New Testament with its " <>
          "apparatus, the UBS Hebrew Old Testament Text Project",
      "licence" =>
        "Samaritan Pentateuch (DT-UCPH/sp, Højgaard, Naaijer & Schorch): CC BY-NC 4.0 " <>
          "(non-commercial); SBLGNT and its apparatus (SBL and Logos Bible Software): CC BY 4.0; " <>
          "HOTTP (United Bible Societies): CC BY-SA 4.0. Each in its own tables"
    }
  }

  @doc "Where the packs are served from."
  @spec public_base() :: String.t()
  def public_base, do: @public_base

  @doc "The object key of a pack file in data version `version`."
  @spec key(pos_integer(), String.t()) :: String.t()
  def key(version, name), do: "packs/v#{version}/#{name}.sqlite.zst"

  @doc """
  The base packs' manifest entries, in the published manifest's order:
  `base.json`'s pins, with description, licence, `required` and tables from
  the published manifest's entry of the same name. Returns
  `{:error, reasons}` if the published manifest lacks a base pack or lists
  it with other files than `base.json` pins (someone published a different
  base; stop and look).
  """
  @spec base_entries(map(), map()) :: {:ok, [map()]} | {:error, [String.t()]}
  def base_entries(%{"packs" => pins}, %{"packs" => published}) do
    listed = Enum.map(published, & &1["name"])

    missing =
      for name <- Map.keys(pins), name not in listed, do: "#{name}: not in the published manifest"

    results =
      for %{"name" => name} = entry <- published, pin = pins[name] do
        case Enum.reject(@checked, &(entry[&1] == pin[&1])) do
          [] ->
            {:ok,
             entry
             |> Map.take(~w(description required licence tables))
             |> Map.merge(pin)
             |> Map.merge(%{"name" => name, "compression" => "zstd"})}

          fields ->
            {:error, "#{name}: published #{Enum.join(fields, ", ")} differ from base.json"}
        end
      end

    case missing ++ for({:error, reason} <- results, do: reason) do
      [] -> {:ok, for({:ok, entry} <- results, do: entry)}
      reasons -> {:error, reasons}
    end
  end

  @doc """
  `:ok` if a scrolls pack's `meta` (its pack_meta) says it was built from
  `expected`'s sources: `dss_sha256` and `dss_source` (the pinned ETCBC/dss
  files), `core_sha256` (base.json's core pack) and `build_sha256` (this
  checkout's code, `Bezalel.Data.Scrolls.build_digest/0`); else
  `{:error, reason}`.
  """
  @spec check_scrolls(map(), map()) :: :ok | {:error, String.t()}
  def check_scrolls(meta, expected) do
    cond do
      meta["dss_sha256"] != expected.dss_sha256 or meta["dss_source"] != expected.dss_source ->
        {:error, "wasn't built from pins.json's ETCBC/dss"}

      meta["core_sha256"] != expected.core_sha256 ->
        {:error, "wasn't numbered with base.json's core pack"}

      meta["build_sha256"] != expected.build_sha256 ->
        {:error, "was built by other code than this checkout's"}

      true ->
        :ok
    end
  end

  @doc """
  `:ok` if a translations pack's `meta` (its pack_meta) says it was built
  from `expected`'s sources (string keys, as pack_meta has them):
  `net_sha256`, `jps_sha256`, `ult_sha256`, `ust_sha256` (the pinned
  downloads' digests) and `core_sha256` (base.json's core pack, which
  numbers the JPS); else `{:error, reason}` naming what differs.
  """
  @spec check_translations(map(), map()) :: :ok | {:error, String.t()}
  def check_translations(meta, expected) do
    sources =
      for key <- ~w(net jps ult ust), meta["#{key}_sha256"] != expected["#{key}_sha256"], do: key

    cond do
      sources != [] ->
        {:error, "wasn't built from pins.json's #{Enum.join(sources, ", ")}"}

      meta["core_sha256"] != expected["core_sha256"] ->
        {:error, "wasn't numbered with base.json's core pack"}

      true ->
        :ok
    end
  end

  @doc """
  `:ok` if a fathers pack's `meta` (its pack_meta) says it was built from
  `expected`'s sources: `fathers_sha256` (the pinned Greek and English
  files), `greek_source` and `english_source` (their commits) and
  `build_sha256` (this checkout's code, `Bezalel.Data.Fathers.build_digest/0`);
  else `{:error, reason}`.
  """
  @spec check_fathers(map(), map()) :: :ok | {:error, String.t()}
  def check_fathers(meta, expected) do
    cond do
      meta["fathers_sha256"] != expected.fathers_sha256 or
        meta["greek_source"] != expected.greek_source or
          meta["english_source"] != expected.english_source ->
        {:error, "wasn't built from pins.json's Apostolic Fathers files"}

      meta["build_sha256"] != expected.build_sha256 ->
        {:error, "was built by other code than this checkout's"}

      true ->
        :ok
    end
  end

  @doc """
  `:ok` if a dictionaries pack's `meta` says it was built from `expected`'s
  sources: `ubs_sha256` and `ubs_source` (the pinned UBS files),
  `core_sha256` (base.json's core pack, which numbers its references) and
  `build_sha256` (`Bezalel.Data.Dictionaries.build_digest/0`); else
  `{:error, reason}`.
  """
  @spec check_dictionaries(map(), map()) :: :ok | {:error, String.t()}
  def check_dictionaries(meta, expected) do
    cond do
      meta["ubs_sha256"] != expected.ubs_sha256 or meta["ubs_source"] != expected.ubs_source ->
        {:error, "wasn't built from pins.json's UBS dictionaries"}

      meta["core_sha256"] != expected.core_sha256 ->
        {:error, "wasn't numbered with base.json's core pack"}

      meta["build_sha256"] != expected.build_sha256 ->
        {:error, "was built by other code than this checkout's"}

      true ->
        :ok
    end
  end

  @doc """
  `:ok` if a syntax pack's `meta` (its pack_meta) says it was built from
  `expected`'s sources: `macula_sha256` and `macula_source` (the pinned
  MACULA files), `core_sha256` (base.json's core pack) and `build_sha256`
  (this checkout's code, `Bezalel.Data.Syntax.build_digest/0`); else
  `{:error, reason}`.
  """
  @spec check_syntax(map(), map()) :: :ok | {:error, String.t()}
  def check_syntax(meta, expected) do
    cond do
      meta["macula_sha256"] != expected.macula_sha256 or
          meta["macula_source"] != expected.macula_source ->
        {:error, "wasn't built from pins.json's MACULA files"}

      meta["core_sha256"] != expected.core_sha256 ->
        {:error, "wasn't numbered with base.json's core pack"}

      meta["build_sha256"] != expected.build_sha256 ->
        {:error, "was built by other code than this checkout's"}

      true ->
        :ok
    end
  end

  @doc """
  `:ok` if a witnesses pack's `meta` says it was built from `expected`'s
  sources: `sp_sha256`, `sblgnt_sha256` and `hottp_sha256` (the digests of
  `pins.json`'s files, `Bezalel.Data.Witnesses.digest/1`), `core_sha256`
  (base.json's core pack) and `build_sha256` (this checkout's code,
  `Bezalel.Data.Witnesses.build_digest/0`); else `{:error, reason}`.
  """
  @spec check_witnesses(map(), map()) :: :ok | {:error, String.t()}
  def check_witnesses(meta, expected) do
    sources = [sp_sha256: "sp", sblgnt_sha256: "sblgnt", hottp_sha256: "hottp"]

    case Enum.find(sources, fn {key, _pin} -> meta[Atom.to_string(key)] != expected[key] end) do
      {_key, pin} ->
        {:error, "wasn't built from pins.json's #{pin}"}

      nil ->
        cond do
          meta["core_sha256"] != expected.core_sha256 ->
            {:error, "wasn't numbered with base.json's core pack"}

          meta["build_sha256"] != expected.build_sha256 ->
            {:error, "was built by other code than this checkout's"}

          true ->
            :ok
        end
    end
  end

  @doc "The names of the packs built here, in manifest order."
  @spec built_here() :: [String.t()]
  def built_here, do: ~w(translations scrolls fathers dictionaries syntax witnesses)

  @doc """
  The manifest entry of pack `name` (one of `built_here/0`) for a pack
  file: `zst` the compressed bytes' `%{size, sha256}`, `raw` the SQLite
  file's, `tables` from its pack_meta. Every pack built here is optional.
  """
  @spec entry(String.t(), pos_integer(), map(), map(), [String.t()]) :: map()
  def entry(name, version, zst, raw, tables) do
    Map.merge(Map.fetch!(@built_here, name), %{
      "name" => name,
      "required" => false,
      "url" => "#{@public_base}/#{key(version, name)}",
      "compression" => "zstd",
      "size" => zst.size,
      "sha256" => zst.sha256,
      "raw_size" => raw.size,
      "raw_sha256" => raw.sha256,
      "tables" => tables
    })
  end

  @doc """
  The next manifest. `opts`: `:version` (the data version, one more than the
  published one), `:built` (ISO 8601 UTC), `:core_commit` (the bezalel_core
  commit whose `data/` built the new packs). `bezalel_commit` stays the
  phone-app commit that built the base.
  """
  @spec manifest(map(), [map()], [map()], keyword()) :: map()
  def manifest(base, base_entries, new_entries, opts) do
    names = Enum.map(new_entries, & &1["name"])

    %{
      "schema" => 1,
      "data_version" => Keyword.fetch!(opts, :version),
      "built" => Keyword.fetch!(opts, :built),
      "bezalel_commit" => base["bezalel_mob_commit"],
      "bezalel_core" => %{"repo" => @core_repo, "commit" => Keyword.fetch!(opts, :core_commit)},
      "studybible_mcp" => base["studybible_mcp"],
      "sources" => @sources,
      "packs" => Enum.reject(base_entries, &(&1["name"] in names)) ++ new_entries
    }
  end

  @doc "The manifest as the published file: pretty JSON, keys in a fixed order, final newline."
  @spec encode(map()) :: binary()
  def encode(manifest) do
    manifest |> object(@top_keys) |> Jason.encode!(pretty: true) |> Kernel.<>("\n")
  end

  # A JSON object with `keys` first, in that order, then any others sorted.
  defp object(map, keys) do
    present = Map.keys(map)

    (Enum.filter(keys, &(&1 in present)) ++ Enum.sort(present -- keys))
    |> Enum.map(fn key -> {key, value(key, map[key])} end)
    |> Jason.OrderedObject.new()
  end

  defp value("packs", packs) when is_list(packs), do: Enum.map(packs, &object(&1, @entry_keys))
  defp value(_key, map) when is_map(map), do: object(map, ~w(repo commit))
  defp value(_key, value), do: value
end
