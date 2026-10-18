defmodule Bezalel.MaterialsTest do
  # Configures :bezalel_core, :materials (the store).
  use ExUnit.Case, async: false

  alias Bezalel.Materials
  alias Bezalel.Materials.Material
  alias Bezalel.Test.MaterialStore

  # A store that sends models a smaller copy of a picture, as a phone does.
  defmodule ResizingStore do
    @behaviour Bezalel.Materials.Store
    alias Bezalel.Test.MaterialStore

    @impl true
    defdelegate put(m, bytes, ctx), to: MaterialStore
    @impl true
    defdelegate fetch(id, ctx), to: MaterialStore
    @impl true
    defdelegate read(m, ctx), to: MaterialStore
    @impl true
    defdelegate derivatives(id, ctx), to: MaterialStore

    @impl true
    def for_model(m, _ctx), do: {:ok, {"image/jpeg", "small:" <> m.id}}
  end

  @ctx %{session_id: "s1"}
  @at ~U[2026-10-18 09:00:00Z]

  defp video, do: Materials.new("video bytes", name: "Sermon.mov", meta: %{duration_ms: 151_000})

  describe "records" do
    test "a material is named by the SHA-256 of its bytes" do
      assert Materials.id("abc") ==
               "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"

      assert Materials.new("abc", name: "a.jpg").id == Materials.id("abc")
      assert Materials.new("abc", name: "b.png").id == Materials.new("abc", name: "a.jpg").id
    end

    test "its kind and media type follow from its name, phone formats included" do
      photo = Materials.new("x", name: "IMG_0412.HEIC")

      assert {photo.kind, photo.mime, photo.size, photo.source} ==
               {:image, "image/heic", 1, :sent}

      assert Materials.new("x", name: "memo.m4a").mime == "audio/mp4"
      assert Materials.new("x", name: "memo.m4a").kind == :audio
      assert Materials.new("x", name: "clip.MOV").kind == :video
      assert Materials.new("x", name: "notes.pdf").kind == :document
      assert Materials.kind("audio/webm; codecs=opus") == :audio
    end

    test "an unknown kind, source or derivation is refused" do
      assert_raise ArgumentError, fn -> Materials.new("x", derivation: :thumbnail) end
      assert_raise ArgumentError, fn -> Materials.new("x", source: :uploaded) end
    end

    test "derivatives name what they came from" do
      v = video()
      t = Materials.derive(:transcript, v, "what was said")

      assert %Material{kind: :transcript, mime: "text/plain", source: :derived} = t
      assert t.derivation == :transcript
      assert t.derived_from == [v.id]
      assert t.name == "Sermon transcript.txt"

      still = Materials.derive(:still, v, "jpeg", meta: %{at_ms: 62_000})
      assert {still.kind, still.mime, still.name} == {:image, "image/jpeg", "Sermon at 1:02.jpg"}

      track = Materials.derive(:audio_track, v, "pcm")
      assert {track.kind, track.name} == {:audio, "Sermon audio.wav"}
    end

    test "a drawing is received, not derived, and names its reference pictures" do
      photo = Materials.new("photo", name: "IMG.jpg")
      drawing = Materials.derive(:generated, [photo], "png")

      assert {drawing.kind, drawing.source, drawing.derived_from} ==
               {:image, :received, [photo.id]}

      assert Materials.derive(:generated, [], "png").derived_from == []
    end

    test "the file layout is the id under its first two digits, with the type's extension" do
      m = Materials.new("abc", name: "a.jpeg")
      assert Materials.relative_path(m) == "ba/#{m.id}.jpg"
      assert Materials.path("/data/materials", m) == "/data/materials/ba/#{m.id}.jpg"

      assert Materials.extension("audio/mp4") == "m4a"
      assert Materials.extension("text/plain; charset=utf-8") == "txt"
      assert Materials.extension("application/pdf") == "pdf"
      assert Materials.extension("application/x-unheard-of") == "bin"
    end

    @tag :tmp_dir
    test "write_file writes once, through a temporary file, and checks the bytes", %{tmp_dir: dir} do
      m = Materials.new("abc", name: "a.jpg")
      assert {:ok, path} = Materials.write_file(dir, m, "abc")
      assert File.read!(path) == "abc"
      assert {:ok, ^path} = Materials.write_file(dir, m, "abc")
      assert File.ls!(Path.dirname(path)) == [Path.basename(path)]

      assert Materials.write_file(dir, m, "abd") == {:error, :id_mismatch}
    end

    test "to_map/from_map round-trip through JSON" do
      v = video()

      t =
        Materials.derive(:transcript, v, "text",
          inserted_at: @at,
          meta: %{model: "whisper", lang: "en"}
        )

      back = t |> Materials.to_map() |> Jason.encode!() |> Jason.decode!() |> Materials.from_map()

      assert back == %{t | meta: %{"lang" => "en", model: "whisper"}}
    end

    test "about/1 is one line of what's known" do
      photo =
        Materials.new(:binary.copy("x", 1_234_567),
          name: "IMG.jpg",
          meta: %{width: 3024, height: 4032}
        )

      assert Materials.about(photo) == "image · 3024×4032 · 1.2 MB"
      assert Materials.about(video()) == "video · 2:31 · 11 bytes"

      pdf = Materials.new(:binary.copy("x", 240_000), name: "a.pdf", meta: %{pages: 3})
      assert Materials.about(pdf) == "PDF · 3 pages · 240 KB"
    end

    test "the video notice is Kevin's wording" do
      assert Materials.video_notice() ==
               "Bezalel doesn't watch videos. It reads what's said (a transcript) and the stills " <>
                 "you choose. On-screen text, gestures, music and anything not spoken or in a " <>
                 "still won't reach it."
    end
  end

  describe "route/3" do
    test "pictures attach; a PDF attaches only to a model that takes PDFs" do
      photo = Materials.new("p", name: "IMG.jpg")
      pdf = Materials.new("pdf", name: "paper.pdf")

      assert Materials.route([photo, pdf], [:text, :image, :pdf], []) ==
               [{:attach, photo}, {:attach, pdf}]

      assert Materials.route([pdf], [:text, :image], []) == [{:file, pdf}]

      text = Materials.derive(:transcript, pdf, "the paper's text")
      assert Materials.route([pdf], [:text, :image], [text]) == [{:text, pdf, text}]
    end

    test "audio and video go as their newest transcript, through the audio track too" do
      v = video()
      track = Materials.derive(:audio_track, v, "pcm")
      old = Materials.derive(:transcript, track, "old", inserted_at: ~U[2026-10-01 00:00:00Z])
      new = Materials.derive(:transcript, track, "new", inserted_at: @at)
      other = Materials.derive(:transcript, Materials.new("x", name: "x.m4a"), "not this")

      assert Materials.route([v], [:text, :image, :audio, :video], [old, other, track, new]) ==
               [{:text, v, new}]
    end

    test "audio or video without a transcript is reported missing" do
      memo = Materials.new("m", name: "memo.m4a")
      assert Materials.route([memo], [:text], []) == [{:missing, memo}]
    end

    test "a text file is its own text; other documents go by name" do
      notes = Materials.new("# Notes", name: "notes.md")
      docx = Materials.new("PK", name: "essay.docx")
      json = Materials.new("{}", name: "data.json")

      assert Materials.route([notes, docx, json], [:text], []) ==
               [{:text, notes, notes}, {:file, docx}, {:text, json, json}]
    end
  end

  describe "with the host's store" do
    setup do
      MaterialStore.install()
      :ok
    end

    defp keep(m, bytes, ctx \\ @ctx) do
      {:ok, m} = Materials.put(m, bytes, ctx)
      m
    end

    test "attachments/4 sends only the ctx's owner's materials and derivatives" do
      theirs =
        keep(Materials.new("their notes", name: "notes.txt"), "their notes", %{session_id: "s2"})

      assert Materials.attachments([theirs], [:text], @ctx) == {:error, {:not_found, theirs.id}}

      assert Materials.attachments([theirs.id], [:text], @ctx) ==
               {:error, {:not_found, theirs.id}}

      # The same video in both sessions; only the other one has a transcript.
      mine = keep(video(), "video bytes")
      other = keep(video(), "video bytes", %{session_id: "s2"})
      text = "their transcript"
      keep(Materials.derive(:transcript, other, text), text, %{session_id: "s2"})

      assert Materials.attachments([mine.id], [:text], @ctx) == {:missing, [mine]}
    end

    test "attachments/4 builds rho's attachments by reference" do
      photo = keep(Materials.new("p", name: "IMG.jpg", meta: %{width: 2, height: 3}), "p")
      v = keep(video(), "video bytes")
      keep(Materials.derive(:transcript, v, "In the beginning"), "In the beginning")

      assert {:ok, [image, transcript]} = Materials.attachments([photo, v], [:text, :image], @ctx)

      assert image == %{
               kind: :image,
               ref: photo.id,
               name: "IMG.jpg",
               mime: "image/jpeg",
               about: "image · 2×3 · 1 bytes"
             }

      assert %{kind: :text, ref: ref, mime: "video/quicktime", text: "In the beginning"} =
               transcript

      assert ref == v.id
      assert transcript.about =~ "what's said in it (a transcript); the video itself isn't sent"

      # rho stores them as references: no bytes in the session.
      entry = Rho.Session.user("what is this?", attachments: [image, transcript])
      content = entry["message"]["content"]
      refute Enum.any?(content, &(&1["type"] == "image"))
      assert Enum.any?(content, &(&1["text"] =~ ~s|ref="#{photo.id}"|))
      assert Enum.any?(content, &(&1["text"] =~ "In the beginning"))
    end

    test "attachments/4 names what still needs a transcript" do
      memo = keep(Materials.new("m", name: "memo.m4a"), "m")
      photo = keep(Materials.new("p", name: "IMG.jpg"), "p")
      assert Materials.attachments([photo, memo], [:text, :image], @ctx) == {:missing, [memo]}
    end

    test "attachments/4 cuts a long text" do
      notes = keep(Materials.new("abcdefghij", name: "notes.txt"), "abcdefghij")

      assert {:ok, [%{text: text}]} = Materials.attachments([notes], [:text], @ctx, text_max: 4)
      assert text == "abcd\n(cut here: 6 more characters not sent)"
    end

    test "resolve/2 gives rho a referenced file's bytes, only to its owner's session" do
      photo = keep(Materials.new("p", name: "IMG.png"), "p")
      attachment = %{"kind" => "image", "ref" => photo.id, "mimeType" => "image/png"}

      assert Materials.resolve(attachment, @ctx) == {:ok, {"image/png", "p"}}
      assert Materials.resolve(attachment, %{session_id: "s2"}) == {:error, :not_found}
      assert Materials.resolve(%{"kind" => "image"}, @ctx) == {:error, :no_ref}
    end

    test "resolve/2 sends the store's copy for models when it has one" do
      Application.put_env(:bezalel_core, :materials, ResizingStore)
      photo = keep(Materials.new("p", name: "IMG.heic"), "p")

      assert Materials.resolve(%{"ref" => photo.id}, @ctx) ==
               {:ok, {"image/jpeg", "small:" <> photo.id}}
    end

    @tag :capture_log
    test "rho fetches a referenced picture through resolve/2 when it builds the request" do
      previous = Application.fetch_env(:rho, :resolve_attachment)
      Application.put_env(:rho, :resolve_attachment, {Materials, :resolve, []})

      on_exit(fn ->
        case previous do
          {:ok, v} -> Application.put_env(:rho, :resolve_attachment, v)
          :error -> Application.delete_env(:rho, :resolve_attachment)
        end
      end)

      photo = keep(Materials.new("png bytes", name: "IMG.png"), "png bytes")
      {:ok, attachments} = Materials.attachments([photo], [:text, :image], @ctx)
      entry = Rho.Session.user("what's this?", attachments: attachments)

      [message] = Rho.Session.messages([entry], inputs: [:text, :image], session_id: "s1")
      assert Enum.any?(message.content, &(&1.type == :image and &1.data == "png bytes"))

      # Another user's session doesn't find it: rho sends a note instead.
      [message] = Rho.Session.messages([entry], inputs: [:text, :image], session_id: "s2")
      refute Enum.any?(message.content, &(&1.type == :image))
    end
  end

  test "without a store, nothing is kept or found" do
    previous = Application.fetch_env(:bezalel_core, :materials)
    Application.delete_env(:bezalel_core, :materials)

    on_exit(fn ->
      with {:ok, v} <- previous, do: Application.put_env(:bezalel_core, :materials, v)
    end)

    m = Materials.new("p", name: "IMG.jpg")
    assert Materials.put(m, "p", @ctx) == {:error, :no_store}
    assert Materials.fetch(m.id, @ctx) == :error
    assert Materials.derivatives(m.id, @ctx) == []
    assert Materials.resolve(%{"ref" => m.id}, @ctx) == {:error, :no_store}
  end

  test "a store that doesn't load or lacks a callback is refused, not called" do
    previous = Application.fetch_env(:bezalel_core, :materials)

    on_exit(fn ->
      case previous do
        {:ok, v} -> Application.put_env(:bezalel_core, :materials, v)
        :error -> Application.delete_env(:bezalel_core, :materials)
      end
    end)

    for bad <- [MyApp.NoSuchStore, Enum, "not a module"] do
      Application.put_env(:bezalel_core, :materials, bad)
      assert Materials.store() == {:error, {:bad_store, bad}}
      assert Materials.put(Materials.new("p"), "p", @ctx) == {:error, {:bad_store, bad}}
      assert Materials.fetch("x", @ctx) == :error
    end
  end
end
