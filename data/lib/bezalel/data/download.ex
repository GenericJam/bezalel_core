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
end
