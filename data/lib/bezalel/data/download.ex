defmodule Bezalel.Data.Download do
  @moduledoc """
  Downloads into `work/` and reads the pins (`pins.json`).

  A cached download is reused while it passes its check; otherwise it is
  fetched again. A fresh download that fails the check is kept beside the
  cache as `<name>.unverified` for review, and never replaces the cache.
  """

  @pins Path.expand("../../../pins.json", __DIR__)

  @doc "The pin for `source` in `pins.json`, with string keys."
  @spec pin!(String.t()) :: map()
  def pin!(source) do
    case @pins |> File.read!() |> Jason.decode!() |> Map.fetch(source) do
      {:ok, pin} -> pin
      :error -> raise ArgumentError, "pins.json has no #{inspect(source)}"
    end
  end

  @doc """
  The bytes of `url`, cached at `path`, if they pass `check` (bytes →
  `:ok | {:error, message}`). Returns `{:ok, bytes}` or `{:error, message}`.
  """
  @spec fetch(String.t(), Path.t(), (binary() -> :ok | {:error, String.t()})) ::
          {:ok, binary()} | {:error, String.t()}
  def fetch(url, path, check) do
    cached = if File.regular?(path), do: File.read!(path)

    if is_binary(cached) and check.(cached) == :ok do
      {:ok, cached}
    else
      download(url, path, check)
    end
  end

  defp download(url, path, check) do
    IO.puts("Downloading #{url}")
    bytes = Req.get!(url, decode_body: false, retry: :transient).body
    # One request at a time, a moment apart: these are free public services.
    Process.sleep(250)
    File.mkdir_p!(Path.dirname(path))

    case check.(bytes) do
      :ok ->
        File.write!(path, bytes)
        File.rm(path <> ".unverified")
        {:ok, bytes}

      {:error, message} ->
        File.write!(path <> ".unverified", bytes)
        {:error, "#{url}: #{message} (kept as #{path}.unverified)"}
    end
  end

  @base Path.expand("../../../base.json", __DIR__)

  @doc """
  The path of the base core pack (`base.json` → `packs.core`), whose
  `verses.reference` maps Hebrew to English numbering (`Psa.3.0(3.1)`):
  `path` if given (e.g. the phone app's `data/out/core.sqlite`), else
  downloaded from `base.json`'s URL into `work/base/` and decompressed with
  `zstd`. Either way its sha256 must be `base.json`'s `raw_sha256`.
  """
  @spec base_core!(Path.t() | nil) :: Path.t()
  def base_core!(path) do
    pin = @base |> File.read!() |> Jason.decode!() |> get_in(["packs", "core"])
    path = path || download_base_core!(pin)

    if sha256(File.read!(path)) != pin["raw_sha256"] do
      Mix.raise("#{path} is not the base core pack (sha256 differs from base.json)")
    end

    path
  end

  defp download_base_core!(pin) do
    zst = Path.join(["work", "base", "core.sqlite.zst"])
    check = &if(sha256(&1) == pin["sha256"], do: :ok, else: {:error, "sha256 differs"})

    case fetch(pin["url"], zst, check) do
      {:ok, _bytes} -> :ok
      {:error, message} -> Mix.raise("base core pack: #{message}")
    end

    raw = Path.join(["work", "base", "core.sqlite"])

    unless File.regular?(raw) and sha256(File.read!(raw)) == pin["raw_sha256"] do
      {_, 0} = System.cmd("zstd", ["-d", "-q", "-f", zst, "-o", raw])
    end

    raw
  end

  defp sha256(bytes), do: :crypto.hash(:sha256, bytes) |> Base.encode16(case: :lower)
end
