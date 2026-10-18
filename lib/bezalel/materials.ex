defmodule Bezalel.Materials do
  @moduledoc """
  Materials: the files sent to the agent and received from it (photos,
  screenshots, audio, video, documents) and what Bezalel makes from them
  (transcripts, audio tracks, stills, drawings). Bezalel worked "gold,
  silver, bronze, cutting stones, carving wood" (Ex 31:4–5): what comes to
  the bench and what comes off it.

  A material (`Bezalel.Materials.Material`) is named by the SHA-256 of its
  bytes (`id/1`), so the same file sent twice is one material, and its
  file's place under a host directory follows from that
  (`relative_path/1`, `write_file/3`). Derivatives say what they were made
  from (`derive/4`): a video's audio track, the track's transcript, a still
  at a time, a drawing from reference pictures. Originals are kept beside
  their derivatives.

  **What goes to the model** (`route/3`, `attachments/4`), by what the
  model takes (`Rho.Models.inputs/1`):

    * an image goes as a picture, by reference (rho resolves the reference
      when it calls the model, `resolve/2`; a model without `:image` gets
      rho's note instead);
    * a PDF goes as a document when the model takes `:pdf`, else as its
      extracted text (its `:transcript` derivative) when there is one, else
      by name only;
    * audio and video go as their transcript (and the stills the user
      chose, sent as images of their own): no model Bezalel runs watches a
      video, and rho sends no sound. A transcript is kept even for a model
      that hears audio, for search and the chat. One without a transcript
      is reported missing, for the host to transcribe first;
    * a text file goes as its text; any other document by name only.

  **Where materials are kept** is the host's: `config :bezalel_core,
  :materials, MyApp.MaterialStore`, a `Bezalel.Materials.Store`. rho's
  resolver hook points here: `config :rho, :resolve_attachment,
  {Bezalel.Materials, :resolve, []}`.

  `video_notice/0` is what the user reads before sending a video, the same
  words in every app.
  """

  alias Bezalel.Materials.Material

  @kinds [:image, :audio, :video, :document, :transcript]
  @sources [:sent, :received, :derived]
  @derivations [:transcript, :audio_track, :still, :generated]

  @video_notice "Bezalel doesn't watch videos. It reads what's said (a transcript) and the " <>
                  "stills you choose. On-screen text, gestures, music and anything not spoken " <>
                  "or in a still won't reach it."

  # Phone recordings and photos whose media type `MIME` doesn't know, or
  # spells another way.
  @types %{
    "m4a" => "audio/mp4",
    "aac" => "audio/aac",
    "mp3" => "audio/mpeg",
    "caf" => "audio/x-caf",
    "opus" => "audio/opus",
    "oga" => "audio/ogg",
    "weba" => "audio/webm",
    "3gp" => "video/3gpp",
    "m4v" => "video/x-m4v",
    "heic" => "image/heic",
    "heif" => "image/heif"
  }

  # A file's extension for a media type: the common one first.
  @extensions %{
    "audio/mp4" => "m4a",
    "audio/aac" => "aac",
    "audio/mpeg" => "mp3",
    "audio/x-caf" => "caf",
    "audio/opus" => "opus",
    "audio/ogg" => "ogg",
    "audio/webm" => "weba",
    "audio/wav" => "wav",
    "audio/x-wav" => "wav",
    "image/jpeg" => "jpg",
    "image/heic" => "heic",
    "image/heif" => "heif",
    "text/plain" => "txt",
    "text/markdown" => "md",
    "video/3gpp" => "3gp",
    "video/x-m4v" => "m4v"
  }

  # Documents whose bytes are text the model can read as they are.
  @text_types ["application/json", "application/xml", "application/x-yaml", "application/yaml"]

  # A transcript or a document's text is cut to this many characters.
  @text_max 100_000

  # ── Records ──────────────────────────────────────────────────────────────

  @doc "A material's id: the SHA-256 of its bytes, lowercase hex."
  @spec id(binary()) :: String.t()
  def id(bytes) when is_binary(bytes),
    do: :sha256 |> :crypto.hash(bytes) |> Base.encode16(case: :lower)

  @doc """
  A new material from its bytes. `attrs` (keyword or map): `:name` (default
  `"material"`), `:mime` (default from the name, `mime/1`), `:source`
  (default `:sent`, or what the derivation implies), `:derivation`,
  `:derived_from` (ids), `:meta`, `:kind` (default from the media type and
  derivation), `:inserted_at` (default now).
  """
  @spec new(binary(), keyword() | map()) :: Material.t()
  def new(bytes, attrs \\ []) when is_binary(bytes) do
    attrs = Map.new(attrs)
    name = attrs[:name] || "material"
    mime = attrs[:mime] || mime(name)
    derivation = check(attrs[:derivation], [nil | @derivations], :derivation)

    %Material{
      id: id(bytes),
      kind: check(attrs[:kind] || kind(mime, derivation), @kinds, :kind),
      mime: mime,
      name: name,
      size: byte_size(bytes),
      source: check(attrs[:source] || source(derivation), @sources, :source),
      derivation: derivation,
      derived_from: attrs[:derived_from] || [],
      meta: attrs[:meta] || %{},
      inserted_at: attrs[:inserted_at] || DateTime.truncate(DateTime.utc_now(), :second)
    }
  end

  defp check(value, allowed, field) do
    if value in allowed,
      do: value,
      else:
        raise(ArgumentError, "#{field} must be one of #{inspect(allowed)}, got #{inspect(value)}")
  end

  defp source(:generated), do: :received
  defp source(nil), do: :sent
  defp source(_derivation), do: :derived

  @doc """
  A material made from `from` (one material or several): a `:transcript`
  (text, `text/plain`), an `:audio_track` (give its `:mime`), a `:still`
  (`image/jpeg` unless given; put its time in `meta.at_ms`) or a
  `:generated` picture (`image/png` unless given; received, not derived).
  Its name follows the first parent's unless `attrs` names it.
  """
  @spec derive(Material.derivation(), Material.t() | [Material.t()], binary(), keyword() | map()) ::
          Material.t()
  def derive(derivation, from, bytes, attrs \\ []) do
    parents = List.wrap(from)
    attrs = Map.new(attrs)
    mime = attrs[:mime] || default_mime(derivation)
    base = parents |> List.first() |> base_name()

    attrs
    |> Map.merge(%{derivation: derivation, derived_from: Enum.map(parents, & &1.id), mime: mime})
    |> Map.put_new_lazy(:name, fn -> derived_name(derivation, base, attrs, mime) end)
    |> then(&new(bytes, &1))
  end

  defp default_mime(:transcript), do: "text/plain"
  defp default_mime(:audio_track), do: "audio/wav"
  defp default_mime(:still), do: "image/jpeg"
  defp default_mime(:generated), do: "image/png"

  defp base_name(nil), do: nil
  defp base_name(%Material{name: name}), do: Path.rootname(name)

  defp derived_name(:generated, _base, _attrs, mime), do: "Drawing." <> extension(mime)

  defp derived_name(derivation, nil, attrs, mime),
    do: derived_name(derivation, "Material", attrs, mime)

  defp derived_name(:transcript, base, _attrs, mime), do: "#{base} transcript.#{extension(mime)}"
  defp derived_name(:audio_track, base, _attrs, mime), do: "#{base} audio.#{extension(mime)}"

  defp derived_name(:still, base, attrs, mime) do
    case get_in(attrs, [:meta, :at_ms]) do
      ms when is_integer(ms) -> "#{base} at #{clock(ms)}.#{extension(mime)}"
      _ -> "#{base} still.#{extension(mime)}"
    end
  end

  @doc "The kind of material a media type is: image, audio, video, else document."
  @spec kind(String.t()) :: Material.kind()
  def kind(mime) do
    case mime |> essence() |> String.split("/", parts: 2) do
      ["image", _] -> :image
      ["audio", _] -> :audio
      ["video", _] -> :video
      _ -> :document
    end
  end

  defp kind(_mime, :transcript), do: :transcript
  defp kind(mime, _derivation), do: kind(mime)

  @doc ~S|A file's media type from its name (`"IMG_0412.HEIC"` is `"image/heic"`).|
  @spec mime(String.t()) :: String.t()
  def mime(name) do
    ext = name |> Path.extname() |> String.trim_leading(".") |> String.downcase()
    Map.get(@types, ext) || MIME.from_path(name)
  end

  @doc ~S|The file extension for a media type (`"image/jpeg"` is `"jpg"`; `"bin"` when unknown).|
  @spec extension(String.t()) :: String.t()
  def extension(mime) do
    essence = essence(mime)

    Map.get(@extensions, essence) ||
      case MIME.extensions(essence) do
        [ext | _] -> ext
        [] -> "bin"
      end
  end

  # "text/plain; charset=utf-8" is "text/plain".
  defp essence(mime),
    do: mime |> String.split(";", parts: 2) |> hd() |> String.trim() |> String.downcase()

  @doc """
  The material's file under a host directory: `"ab/abcdef….jpg"`, the
  first two hex digits of the id as a folder (so no folder holds every
  file), then the id and its type's extension (players want one).
  """
  @spec relative_path(Material.t()) :: String.t()
  def relative_path(%Material{id: id, mime: mime}),
    do: Path.join(String.slice(id, 0, 2), "#{id}.#{extension(mime)}")

  @doc "The material's file under `dir` (`relative_path/1`)."
  @spec path(Path.t(), Material.t()) :: Path.t()
  def path(dir, material), do: Path.join(dir, relative_path(material))

  @doc """
  Writes `bytes` to the material's file under `dir`, through a temporary
  file so a half-written one never has the name. A file already there is
  the same bytes (the name is their hash) and is left as it is.
  `{:error, :id_mismatch}` when `bytes` aren't the material's.
  """
  @spec write_file(Path.t(), Material.t(), binary()) :: {:ok, Path.t()} | {:error, term()}
  def write_file(dir, %Material{} = material, bytes) do
    path = path(dir, material)

    cond do
      id(bytes) != material.id ->
        {:error, :id_mismatch}

      File.exists?(path) ->
        {:ok, path}

      true ->
        tmp = "#{path}.#{System.unique_integer([:positive])}.tmp"

        with :ok <- File.mkdir_p(Path.dirname(path)),
             :ok <- File.write(tmp, bytes),
             :ok <- File.rename(tmp, path) do
          {:ok, path}
        else
          error ->
            File.rm(tmp)
            error
        end
    end
  end

  @doc """
  The material as JSON-ready data (string keys, atoms as strings, the time
  in ISO 8601), for a host's table or file; `from_map/1` reads it back.
  """
  @spec to_map(Material.t()) :: map()
  def to_map(%Material{} = m) do
    %{
      "id" => m.id,
      "kind" => Atom.to_string(m.kind),
      "mime" => m.mime,
      "name" => m.name,
      "size" => m.size,
      "source" => Atom.to_string(m.source),
      "derivation" => m.derivation && Atom.to_string(m.derivation),
      "derived_from" => m.derived_from,
      "meta" => Map.new(m.meta, fn {k, v} -> {to_string(k), v} end),
      "inserted_at" => DateTime.to_iso8601(m.inserted_at)
    }
  end

  @meta_keys ~w(duration_ms width height pages at_ms prompt model)a
  @meta_names Map.new(@meta_keys, &{Atom.to_string(&1), &1})

  @doc "A material from `to_map/1`'s data (a meta key Bezalel doesn't know stays a string)."
  @spec from_map(map()) :: Material.t()
  def from_map(%{} = map) do
    {:ok, inserted_at, _offset} = DateTime.from_iso8601(map["inserted_at"])

    %Material{
      id: map["id"],
      kind: atom(map["kind"], @kinds),
      mime: map["mime"],
      name: map["name"],
      size: map["size"],
      source: atom(map["source"], @sources),
      derivation: map["derivation"] && atom(map["derivation"], @derivations),
      derived_from: map["derived_from"] || [],
      meta: Map.new(map["meta"] || %{}, fn {k, v} -> {Map.get(@meta_names, k, k), v} end),
      inserted_at: inserted_at
    }
  end

  defp atom(name, allowed) do
    Enum.find(allowed, &(Atom.to_string(&1) == name)) ||
      raise ArgumentError, "unknown value #{inspect(name)}, expected one of #{inspect(allowed)}"
  end

  @doc """
  One line about the material for the model and the chat: its kind, then
  what's known (`"image · 3024×4032 · 1.2 MB"`, `"video · 2:31 · 48 MB"`,
  `"PDF · 3 pages · 240 KB"`).
  """
  @spec about(Material.t()) :: String.t()
  def about(%Material{meta: meta} = m) do
    [
      label(m),
      meta[:at_ms] && "at #{clock(meta[:at_ms])}",
      meta[:width] && meta[:height] && "#{meta[:width]}×#{meta[:height]}",
      meta[:duration_ms] && clock(meta[:duration_ms]),
      pages(meta[:pages]),
      bytes(m.size)
    ]
    |> Enum.filter(& &1)
    |> Enum.join(" · ")
  end

  defp label(%Material{derivation: :still}), do: "still from a video"
  defp label(%Material{derivation: :generated}), do: "drawing"
  defp label(%Material{derivation: :audio_track}), do: "audio track"
  defp label(%Material{kind: :document} = m), do: if(pdf?(m), do: "PDF", else: "document")
  defp label(%Material{kind: kind}), do: Atom.to_string(kind)

  defp pages(nil), do: nil
  defp pages(1), do: "1 page"
  defp pages(n), do: "#{n} pages"

  defp clock(ms) do
    seconds = div(ms, 1000)
    {h, m, s} = {div(seconds, 3600), div(rem(seconds, 3600), 60), rem(seconds, 60)}
    pad = &String.pad_leading(Integer.to_string(&1), 2, "0")
    if h > 0, do: "#{h}:#{pad.(m)}:#{pad.(s)}", else: "#{m}:#{pad.(s)}"
  end

  defp bytes(n) when n < 1_000, do: "#{n} bytes"
  defp bytes(n) when n < 1_000_000, do: "#{round(n / 1_000)} KB"
  defp bytes(n), do: "#{Float.round(n / 1_000_000, 1)} MB"

  @doc """
  What the user reads before sending a video, so every app says the same:
  "#{@video_notice}"
  """
  @spec video_notice() :: String.t()
  def video_notice, do: @video_notice

  # ── To the model ─────────────────────────────────────────────────────────

  @typedoc """
  How a material goes to the model: `{:attach, m}` as a picture or PDF by
  reference; `{:text, m, text}` as the text of `text` (a transcript, a
  document's text, or `m` itself for a text file); `{:file, m}` by name
  only (nothing the model can read); `{:missing, m}` an audio or video with
  no transcript yet.
  """
  @type route ::
          {:attach, Material.t()}
          | {:text, Material.t(), Material.t()}
          | {:file, Material.t()}
          | {:missing, Material.t()}

  @doc """
  How each of `materials` goes to a model that takes `inputs`
  (`Rho.Models.inputs/1`), given their `derivatives` (any materials; those
  made from them are used: the newest transcript, directly or through an
  audio track). Pure: the host or `attachments/4` acts on it.
  """
  @spec route([Material.t()], [atom()], [Material.t()]) :: [route()]
  def route(materials, inputs, derivatives) do
    Enum.map(materials, &route_one(&1, inputs, derivatives))
  end

  defp route_one(%Material{kind: :image} = m, _inputs, _derivatives), do: {:attach, m}
  defp route_one(%Material{kind: :transcript} = m, _inputs, _derivatives), do: {:text, m, m}

  defp route_one(%Material{kind: kind} = m, _inputs, derivatives) when kind in [:audio, :video] do
    case transcript(m, derivatives) do
      nil -> {:missing, m}
      t -> {:text, m, t}
    end
  end

  defp route_one(%Material{kind: :document} = m, inputs, derivatives) do
    cond do
      pdf?(m) and :pdf in inputs -> {:attach, m}
      text?(m) -> {:text, m, m}
      t = transcript(m, derivatives) -> {:text, m, t}
      true -> {:file, m}
    end
  end

  defp pdf?(m), do: essence(m.mime) == "application/pdf"

  defp text?(m) do
    essence = essence(m.mime)
    String.starts_with?(essence, "text/") or essence in @text_types
  end

  # The newest transcript made from `m`, or from an audio track of it.
  defp transcript(m, derivatives) do
    tracks = for d <- derivatives, d.derivation == :audio_track, m.id in d.derived_from, do: d.id
    sources = [m.id | tracks]

    derivatives
    |> Enum.filter(
      &(&1.derivation == :transcript and Enum.any?(&1.derived_from, fn id -> id in sources end))
    )
    |> Enum.max_by(& &1.inserted_at, DateTime, fn -> nil end)
  end

  @doc """
  The rho attachments (`Rho.Session.attachment/0`, by reference) that send
  `materials` (ids, or materials whose ids are used) with a question to a
  model taking `inputs`. Each is fetched afresh from the host's store with
  `ctx`, so only the ctx's owner's materials go (`{:error, {:not_found,
  id}}` for one the store doesn't give); their derivatives and texts are
  read through it too. The result is the attachments of `Rho.Loop.prompt/3`
  (and `steer/3`, `follow_up/3`) or of `Rho.Session.user/2`
  (`:attachments`).

  `{:missing, materials}` names the audio and video still without a
  transcript: the host transcribes them (storing each transcript with
  `derive(:transcript, …)`) and asks again. `opts[:text_max]` cuts a text
  to that many characters (default #{@text_max}).
  """
  @spec attachments([Material.t() | String.t()], [atom()], map(), keyword()) ::
          {:ok, [map()]} | {:missing, [Material.t()]} | {:error, term()}
  def attachments(materials, inputs, ctx, opts \\ []) do
    max = Keyword.get(opts, :text_max, @text_max)

    with {:ok, materials} <- fetch_all(materials, ctx) do
      routes = route(materials, inputs, Enum.flat_map(materials, &family(&1, ctx)))
      missing = for {:missing, m} <- routes, do: m
      if missing == [], do: collect(routes, ctx, max), else: {:missing, missing}
    end
  end

  defp fetch_all(materials, ctx) do
    Enum.reduce_while(materials, {:ok, []}, fn item, {:ok, acc} ->
      id = if is_binary(item), do: item, else: item.id

      case fetch(id, ctx) do
        {:ok, m} -> {:cont, {:ok, [m | acc]}}
        :error -> {:halt, {:error, {:not_found, id}}}
      end
    end)
    |> then(fn
      {:ok, list} -> {:ok, Enum.reverse(list)}
      error -> error
    end)
  end

  # What was made from `m`, and from its audio tracks.
  defp family(m, ctx) do
    children = derivatives(m.id, ctx)
    tracks = for d <- children, d.derivation == :audio_track, do: d
    children ++ Enum.flat_map(tracks, &derivatives(&1.id, ctx))
  end

  defp collect(routes, ctx, max) do
    Enum.reduce_while(routes, {:ok, []}, fn route, {:ok, acc} ->
      case attachment(route, ctx, max) do
        {:ok, a} -> {:cont, {:ok, [a | acc]}}
        error -> {:halt, error}
      end
    end)
    |> then(fn
      {:ok, list} -> {:ok, Enum.reverse(list)}
      error -> error
    end)
  end

  defp attachment({:attach, m}, _ctx, _max) do
    a = base(m, if(m.kind == :image, do: :image, else: :pdf), about(m))
    {:ok, if(m.meta[:pages], do: Map.put(a, :pages, m.meta[:pages]), else: a)}
  end

  defp attachment({:file, m}, _ctx, _max),
    do: {:ok, base(m, :file, about(m) <> " · Bezalel can't read this kind of file")}

  defp attachment({:text, m, source}, ctx, max) do
    with {:ok, bytes} <- read(source, ctx) do
      {:ok, m |> base(:text, text_about(m, source)) |> Map.put(:text, cut(bytes, max))}
    end
  end

  defp base(m, kind, about),
    do: %{kind: kind, ref: m.id, name: m.name, mime: m.mime, about: about}

  defp text_about(m, m), do: about(m)

  defp text_about(%Material{kind: :video} = m, _t),
    do: about(m) <> " · what's said in it (a transcript); the video itself isn't sent"

  defp text_about(%Material{kind: :audio} = m, _t),
    do: about(m) <> " · what's said in it (a transcript)"

  defp text_about(m, _t), do: about(m) <> " · its text"

  defp cut(bytes, max) do
    text = if String.valid?(bytes), do: bytes, else: :unicode.characters_to_binary(bytes, :latin1)

    if String.length(text) > max,
      do:
        String.slice(text, 0, max) <>
          "\n(cut here: #{String.length(text) - max} more characters not sent)",
      else: text
  end

  @doc """
  rho's attachment resolver (`config :rho, :resolve_attachment,
  {Bezalel.Materials, :resolve, []}`): the bytes of the material a stored
  attachment names (its `"ref"`), from the host's store with `ctx` (rho's:
  `%{session_id: …}`), as `{mime, bytes}` for the model. The store's
  `for_model/2` when it has one (a resized photo), else its bytes as kept.
  """
  @spec resolve(map(), map()) :: {:ok, {String.t(), binary()}} | {:error, term()}
  def resolve(%{"ref" => id}, ctx) when is_binary(id) do
    with {:ok, store} <- store(),
         {:fetch, {:ok, m}} <- {:fetch, store.fetch(id, ctx)} do
      model_bytes(store, m, ctx)
    else
      {:fetch, _} -> {:error, :not_found}
      error -> error
    end
  end

  def resolve(_attachment, _ctx), do: {:error, :no_ref}

  defp model_bytes(store, m, ctx) do
    if function_exported?(store, :for_model, 2) do
      store.for_model(m, ctx)
    else
      with {:ok, bytes} <- store.read(m, ctx), do: {:ok, {m.mime, bytes}}
    end
  end

  # ── The host's store ─────────────────────────────────────────────────────

  @callbacks [put: 3, fetch: 2, read: 2, derivatives: 2]

  @doc """
  The host's `Bezalel.Materials.Store`: `{:error, :no_store}` when none is
  configured, `{:error, {:bad_store, module}}` when the module doesn't load
  or lacks a callback (so a tool fails before it spends anything).
  """
  @spec store() :: {:ok, module()} | {:error, :no_store | {:bad_store, term()}}
  def store do
    case Application.get_env(:bezalel_core, :materials) do
      nil ->
        {:error, :no_store}

      module when is_atom(module) ->
        if store?(module), do: {:ok, module}, else: {:error, {:bad_store, module}}

      other ->
        {:error, {:bad_store, other}}
    end
  end

  defp store?(module) do
    Code.ensure_loaded?(module) and
      Enum.all?(@callbacks, fn {f, arity} -> function_exported?(module, f, arity) end)
  end

  @doc "Keeps `material` and its `bytes` in the host's store (`c:Bezalel.Materials.Store.put/3`)."
  @spec put(Material.t(), binary(), map()) :: {:ok, Material.t()} | {:error, term()}
  def put(%Material{} = material, bytes, ctx) do
    with {:ok, store} <- store(), do: store.put(material, bytes, ctx)
  end

  @doc "The material `id` from the host's store, or `:error`."
  @spec fetch(String.t(), map()) :: {:ok, Material.t()} | :error
  def fetch(id, ctx) do
    case store() do
      {:ok, store} -> store.fetch(id, ctx)
      {:error, _no_store} -> :error
    end
  end

  @doc "A material's bytes from the host's store."
  @spec read(Material.t(), map()) :: {:ok, binary()} | {:error, term()}
  def read(%Material{} = material, ctx) do
    with {:ok, store} <- store(), do: store.read(material, ctx)
  end

  @doc "The materials made from `id`, from the host's store (`[]` without one)."
  @spec derivatives(String.t(), map()) :: [Material.t()]
  def derivatives(id, ctx) do
    case store() do
      {:ok, store} -> store.derivatives(id, ctx)
      {:error, _no_store} -> []
    end
  end
end
