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
  - the packs built here (`translations`, `scrolls`), uploaded under
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
      "description" => "NET Bible English text",
      "licence" =>
        "NET Bible® copyright ©1996, 2019 Biblical Studies Press, L.L.C.: " <>
          "free non-commercial use by permission (netbible.com/copyright)"
    },
    "scrolls" => %{
      "description" =>
        "Dead Sea Scrolls: major non-biblical works and the biblical manuscripts' readings " <>
          "(Hebrew and Aramaic)",
      "licence" =>
        "ETCBC/dss (Martin G. Abegg Jr., James E. Bowley, Edward M. Cook): CC BY-NC 4.0 " <>
          "(non-commercial; https://creativecommons.org/licenses/by-nc/4.0/)"
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

  @doc "The names of the packs built here, in manifest order."
  @spec built_here() :: [String.t()]
  def built_here, do: ~w(translations scrolls)

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
