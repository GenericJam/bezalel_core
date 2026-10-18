defmodule Mix.Tasks.Bezalel.Data.Publish do
  @shortdoc "Publishes the packs built here as the next data version"

  @moduledoc """
  Publishes the packs built here (`out/translations.sqlite`,
  `out/scrolls.sqlite`) as the next data version, on top of the frozen base,
  without uploading the base.

      mix bezalel.data.publish [--dry-run] [--version N]

  1. Reads the published manifest (data version N - 1) and checks that it
     lists the five base packs exactly as `base.json` pins them, and that
     each is still served at its v1 URL with its size.
  2. Checks each pack was built from `pins.json`'s sources, compresses it
     (`zstd -19`, as the base packs were) to `out/<pack>.sqlite.zst` and
     uploads it to `packs/v<N>/<pack>.sqlite.zst`. An object already at that
     key is accepted only if byte-identical (an interrupted publish resumes);
     anything else stops the publish.
  3. Writes the manifest (`Bezalel.Data.Publish`) to `out/manifest.json`
     and uploads it to `packs/manifest.json` last.
  4. Fetches every upload back, with a unique query string so the answer
     comes from R2 rather than an edge copy, and compares size and sha256.

  `--dry-run` does steps 1 and 3 locally and prints what it would upload.
  A real publish needs `data/` committed (the manifest names the commit) and
  wrangler logged in to the Cloudflare account that owns the bucket.
  """

  use Mix.Task

  alias Bezalel.Data.{Books, Download, Net, Pack, Publish, Scrolls}

  @bucket "bezalel-packs"
  @manifest_key "packs/manifest.json"
  @pack_cache "public, max-age=31536000, immutable"
  @base Path.expand("../../../base.json", __DIR__)
  @switches [dry_run: :boolean, version: :integer]

  @impl Mix.Task
  def run(args) do
    {opts, _rest} = OptionParser.parse!(args, strict: @switches)
    dry_run = Keyword.get(opts, :dry_run, false)
    {:ok, _apps} = Application.ensure_all_started(:req)

    commit = commit!(dry_run)
    base = @base |> File.read!() |> Jason.decode!()
    published = @manifest_key |> fetch() |> published!()
    version = version!(opts[:version], published["data_version"])

    base_entries =
      case Publish.base_entries(base, published) do
        {:ok, entries} ->
          entries

        {:error, reasons} ->
          Mix.raise("The published base isn't base.json's:\n" <> Enum.join(reasons, "\n"))
      end

    Enum.each(base_entries, &check_served!/1)

    Mix.shell().info(
      "Publishing data version #{version} (published: #{published["data_version"]})" <>
        if(dry_run, do: " — dry run, nothing is uploaded", else: "")
    )

    entries =
      for name <- Publish.built_here() do
        {zst_path, zst, raw, tables} = compress!(name)
        put_pack!(Publish.key(version, name), zst_path, zst, dry_run)
        Publish.entry(name, version, zst, raw, tables)
      end

    built =
      Publish.built_here()
      |> Enum.map(&File.stat!("out/#{&1}.sqlite", time: :posix).mtime)
      |> Enum.max()
      |> DateTime.from_unix!()
      |> DateTime.to_iso8601()

    manifest =
      Publish.manifest(base, base_entries, entries,
        version: version,
        built: built,
        core_commit: commit
      )

    body = Publish.encode(manifest)
    File.write!("out/manifest.json", body)
    put!(@manifest_key, "out/manifest.json", "application/json", "no-cache", dry_run)

    unless dry_run, do: verify!(@manifest_key, byte_size(body), Net.sha256(body))

    Mix.shell().info(
      "\nManifest (out/manifest.json): #{Publish.public_base()}/#{@manifest_key} -> data version #{version}"
    )
  end

  defp commit!(dry_run) do
    {status, 0} = System.cmd("git", ["status", "--porcelain", "--", "."])

    if status != "" do
      message =
        "bezalel_core data/ has uncommitted changes; commit the code that built the pack first"

      if dry_run, do: Mix.shell().info("Warning: #{message}"), else: Mix.raise(message)
    end

    {commit, 0} = System.cmd("git", ["rev-parse", "HEAD"])
    String.trim(commit)
  end

  defp published!(nil), do: Mix.raise("No published manifest at #{url(@manifest_key)}")
  defp published!(bytes), do: Jason.decode!(bytes)

  defp version!(nil, published), do: published + 1

  defp version!(version, published) when version > published, do: version

  defp version!(version, published) do
    Mix.raise("--version #{version} must be newer than the published #{published}")
  end

  defp check_served!(%{"url" => url, "size" => size, "name" => name}) do
    response = Req.head!(url <> "?publish=" <> nonce(), retry: :transient)
    length = response |> Req.Response.get_header("content-length") |> List.first()

    if response.status != 200 or length != Integer.to_string(size) do
      Mix.raise(
        "#{url}: served #{response.status}, #{inspect(length)} bytes; base.json says #{size}"
      )
    end

    Mix.shell().info("  base #{name}: #{url} (#{size} bytes, unchanged)")
  end

  defp compress!(name) do
    raw_path = "out/#{name}.sqlite"
    unless File.regular?(raw_path), do: Mix.raise("#{raw_path} isn't built")
    meta = raw_path |> Pack.read("SELECT key, value FROM pack_meta") |> Map.new(&List.to_tuple/1)
    if meta["pack"] != name, do: Mix.raise("#{raw_path} is not the #{name} pack")
    check_source!(name, meta)

    zst_path = raw_path <> ".zst"

    {_out, 0} =
      System.cmd("zstd", ["-19", "-q", "-f", "--no-progress", raw_path, "-o", zst_path])

    raw = File.read!(raw_path)
    zst = File.read!(zst_path)

    {zst_path, %{size: byte_size(zst), sha256: Net.sha256(zst)},
     %{size: byte_size(raw), sha256: Net.sha256(raw)}, String.split(meta["tables"])}
  end

  # The pack must have been built from the pinned sources.
  defp check_source!("translations", meta) do
    books = Download.pin!("net")["books"]

    digest =
      Net.digest(Enum.map(Books.all(), fn {code, _, _} -> {code, books[code]} end))

    if meta["net_sha256"] != digest do
      Mix.raise(
        "out/translations.sqlite wasn't built from pins.json's NET; run mix bezalel.data.net"
      )
    end
  end

  defp check_source!("scrolls", meta) do
    pin = Download.pin!("dss")
    digest = pin["files"] |> Enum.sort() |> Net.digest()

    if meta["dss_sha256"] != digest or meta["dss_source"] != Scrolls.provenance(pin).source_url do
      Mix.raise(
        "out/scrolls.sqlite wasn't built from pins.json's ETCBC/dss; run mix bezalel.data.scrolls"
      )
    end
  end

  defp put_pack!(key, path, %{size: size, sha256: sha256}, dry_run) do
    case fetch(key) do
      nil ->
        put!(key, path, "application/zstd", @pack_cache, dry_run)
        unless dry_run, do: verify!(key, size, sha256)

      existing ->
        if Net.sha256(existing) != sha256 do
          Mix.raise(
            "#{url(key)} exists with different content; refusing to overwrite (use --version)"
          )
        end

        Mix.shell().info("  #{key} already uploaded (identical)")
    end
  end

  defp put!(key, path, content_type, cache_control, dry_run) do
    Mix.shell().info(
      "  put #{@bucket}/#{key} (#{File.stat!(path).size} bytes, #{content_type}, #{cache_control})"
    )

    unless dry_run do
      args =
        ~w(-y wrangler@4 r2 object put) ++
          ["#{@bucket}/#{key}", "--file", path, "--remote"] ++
          ["--content-type", content_type, "--cache-control", cache_control]

      {_out, status} = System.cmd("npx", args, into: IO.stream(), stderr_to_stdout: true)
      if status != 0, do: Mix.raise("wrangler failed (exit #{status}) uploading #{key}")
    end
  end

  defp verify!(key, size, sha256) do
    served = fetch(key)

    if served == nil or byte_size(served) != size or Net.sha256(served) != sha256 do
      Mix.raise("#{url(key)}: served object does not match (size, sha256)")
    end

    Mix.shell().info("  verified #{url(key)}")
  end

  # The object at key, or nil if there is none; read from R2, not the edge.
  defp fetch(key) do
    case Req.get!(url(key) <> "?publish=" <> nonce(), decode_body: false, retry: :transient) do
      %{status: 200, body: body} -> body
      %{status: 404} -> nil
      %{status: status} -> Mix.raise("#{url(key)}: HTTP #{status}")
    end
  end

  defp url(key), do: "#{Publish.public_base()}/#{key}"
  defp nonce, do: 16 |> :crypto.strong_rand_bytes() |> Base.encode16(case: :lower)
end
