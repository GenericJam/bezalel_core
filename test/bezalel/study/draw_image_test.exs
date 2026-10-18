defmodule Bezalel.Study.DrawImageTest do
  # Configures :bezalel_core, :draw_image and :materials.
  use ExUnit.Case, async: false

  alias Bezalel.Materials
  alias Bezalel.Study.{Preferences, Tools}
  alias Bezalel.Study.Tools.DrawImage
  alias Bezalel.Test.MaterialStore
  alias ReqLLM.Error.API.Request
  alias ReqLLM.Message.ContentPart

  # Stands in for ReqLLM.generate_image/3 and Rho.Auth.credential/1: no
  # network, no secure store. The tool runs in the test's process.
  defmodule Fake do
    def generate(model, prompt, opts) do
      send(self(), {:generate, model, prompt, opts})

      case Process.get(:image_reply, :ok) do
        :ok ->
          message = %ReqLLM.Message{
            role: :assistant,
            content: [ContentPart.image("drawn", "image/jpeg")]
          }

          {:ok, %ReqLLM.Response{id: "img_1", model: model, context: nil, message: message}}

        {:error, error} ->
          {:error, error}
      end
    end

    def key(provider) when provider in [:openai, :google],
      do: {:ok, %{type: :api_key, key: "#{provider}-key"}}

    def openai_only(:openai), do: key(:openai)
    def openai_only(_provider), do: {:error, :signed_out}

    def signed_out(_provider), do: {:error, :signed_out}
  end

  @ctx %{session_id: "s1", call_id: "call_1"}

  setup do
    MaterialStore.install()
    previous = Application.fetch_env(:bezalel_core, :draw_image)
    use_key({Fake, :key})

    on_exit(fn ->
      case previous do
        {:ok, value} -> Application.put_env(:bezalel_core, :draw_image, value)
        :error -> Application.delete_env(:bezalel_core, :draw_image)
      end
    end)
  end

  defp use_key(credential) do
    Application.put_env(:bezalel_core, :draw_image,
      generate: {Fake, :generate},
      credential: credential
    )
  end

  defp gemini(model \\ "google:gemini-3.1-flash-image"),
    do: Preferences.new(image_model: model)

  defp keep(material, bytes, ctx \\ @ctx) do
    {:ok, material} = Materials.put(material, bytes, ctx)
    material
  end

  test "it is a rho tool, offered with the materials tools, not the study tools" do
    assert Rho.Tool.tool?(DrawImage)
    assert %ReqLLM.Tool{name: "draw_image"} = Rho.Tool.to_req_llm(DrawImage)
    assert Tools.materials() == [DrawImage]
    refute DrawImage in Tools.all()
  end

  test "it draws from words, keeps the drawing and returns it by reference" do
    assert {:ok, {:images, [image], text}} =
             DrawImage.run(%{"prompt" => "Bezalel carving acacia wood, in ink"}, @ctx)

    assert_received {:generate, "openai:gpt-image-2", "Bezalel carving acacia wood, in ink", opts}
    assert opts[:api_key] == "openai-key"
    assert opts[:size] == "1024x1024"
    refute Keyword.has_key?(opts, :source_image)

    assert {:ok, drawing} = Materials.fetch(image.ref, @ctx)
    assert drawing.id == Materials.id("drawn")
    assert {drawing.kind, drawing.source, drawing.derivation} == {:image, :received, :generated}
    assert drawing.derived_from == []

    assert drawing.meta == %{
             prompt: "Bezalel carving acacia wood, in ink",
             model: "openai:gpt-image-2"
           }

    assert image == %{ref: drawing.id, mime: "image/jpeg", name: drawing.name}
    assert drawing.name == "Drawing – Bezalel carving acacia wood, in ink.jpg"
    assert text =~ "ref #{drawing.id}"

    # rho takes the answer as pictures by reference, and stores no bytes.
    assert Rho.ToolRunner.to_result({:ok, {:images, [image], text}}) ==
             {:ok, {:images, [image], text}}

    entry = Rho.Session.tool_result("call_1", "draw_image", text, false, images: [image])
    refute Enum.any?(entry["message"]["content"], &(&1["type"] == "image"))
  end

  test "with a reference picture it edits from that picture" do
    photo = keep(Materials.new("photo bytes", name: "lampstand.png"), "photo bytes")

    assert {:ok, {:images, [image], _text}} =
             DrawImage.run(
               %{
                 "prompt" => "This lampstand in gold",
                 "references" => [photo.id],
                 "size" => "landscape"
               },
               @ctx
             )

    assert_received {:generate, _model, "This lampstand in gold", opts}
    assert opts[:source_image] == "photo bytes"
    assert opts[:source_image_media_type] == "image/png"
    assert opts[:size] == "1536x1024"

    {:ok, drawing} = Materials.fetch(image.ref, @ctx)
    assert drawing.derived_from == [photo.id]
  end

  test "without an OpenAI API key it tells the user where to add one, and draws nothing" do
    use_key({Fake, :signed_out})

    assert {:error, message} = DrawImage.run(%{"prompt" => "a menorah"}, @ctx)
    assert message =~ "needs an OpenAI API key"
    assert message =~ "Settings (OpenAI, API key)"
    refute_received {:generate, _, _, _}
  end

  test "Pictures by a Gemini model: Gemini draws, on the Gemini key, in the shape asked" do
    assert {:ok, {:images, [image], _text}} =
             DrawImage.run(%{"prompt" => "a menorah", "size" => "portrait"}, @ctx, gemini())

    assert_received {:generate, "google:gemini-3.1-flash-image", "a menorah", opts}
    assert opts[:api_key] == "google-key"
    assert opts[:aspect_ratio] == "2:3"
    assert opts[:provider_options][:response_modalities] == ["IMAGE"]
    # OpenAI's options would only be dropped with a warning.
    refute Keyword.has_key?(opts, :size) or Keyword.has_key?(opts, :output_format)

    {:ok, drawing} = Materials.fetch(image.ref, @ctx)
    assert drawing.meta.model == "google:gemini-3.1-flash-image"
  end

  test "Gemini draws from a reference picture sent with the words" do
    photo = keep(Materials.new("photo bytes", name: "lampstand.png"), "photo bytes")

    assert {:ok, {:images, [image], _text}} =
             DrawImage.run(
               %{"prompt" => "This lampstand in gold", "references" => [photo.id]},
               @ctx,
               gemini("google:gemini-3-pro-image")
             )

    assert_received {:generate, "google:gemini-3-pro-image", %ReqLLM.Context{} = context, opts}
    assert opts[:aspect_ratio] == "1:1"
    refute Keyword.has_key?(opts, :source_image)

    assert [%ReqLLM.Message{role: :user, content: [words, picture]}] = context.messages
    assert words.text == "This lampstand in gold"

    assert {picture.type, picture.data, picture.media_type} ==
             {:image, "photo bytes", "image/png"}

    {:ok, drawing} = Materials.fetch(image.ref, @ctx)
    assert drawing.derived_from == [photo.id]
  end

  test "without the chosen provider's key it names that key, even with another provider's" do
    use_key({Fake, :openai_only})

    assert {:error, message} = DrawImage.run(%{"prompt" => "a menorah"}, @ctx, gemini())
    assert message =~ "Gemini 3.1 Flash Image"
    assert message =~ "needs a Gemini API key"
    assert message =~ "Settings (Gemini, API key)"
    assert message =~ "Pictures by"
    refute_received {:generate, _, _, _}
  end

  test "the image models a user can choose, and the default" do
    assert DrawImage.default_model() == "openai:gpt-image-2"
    assert %Preferences{}.image_model == DrawImage.default_model()

    assert Enum.map(DrawImage.models(), &{&1.id, &1.provider}) == [
             {"openai:gpt-image-2", :openai},
             {"google:gemini-3.1-flash-image", :google},
             {"google:gemini-3-pro-image", :google}
           ]

    # Each is a model req_llm can resolve, and makes pictures.
    for %{id: id} <- DrawImage.models() do
      assert {:ok, model} = ReqLLM.model(id)
      assert :image in model.modalities.output
    end
  end

  test "without a working materials store it says so before spending anything" do
    Application.delete_env(:bezalel_core, :materials)

    assert {:error, message} = DrawImage.run(%{"prompt" => "a menorah"}, @ctx)
    assert message =~ "can't keep drawings"

    Application.put_env(:bezalel_core, :materials, MyApp.NoSuchStore)
    assert {:error, message} = DrawImage.run(%{"prompt" => "a menorah"}, @ctx)
    assert message =~ "isn't working"
    refute_received {:generate, _, _, _}
  end

  test "a reference must be one picture of this conversation's, in a format the model takes" do
    theirs = keep(Materials.new("theirs", name: "a.png"), "theirs", %{session_id: "s2"})
    memo = keep(Materials.new("memo", name: "memo.m4a"), "memo")
    photo = keep(Materials.new("p", name: "p.png"), "p")
    heic = keep(Materials.new("heic", name: "IMG.HEIC"), "heic")

    for {refs, error} <- [
          {[theirs.id], "There is no picture with ref"},
          {[memo.id], "memo.m4a isn't a picture"},
          {[heic.id], "IMG.HEIC is image/heic; the image model draws from JPEG, PNG or WebP"},
          {[photo.id, photo.id], "one picture at a time"},
          {"not a list", "is a list"}
        ] do
      assert {:error, message} = DrawImage.run(%{"prompt" => "x", "references" => refs}, @ctx)
      assert message =~ error
    end

    assert {:error, _} = DrawImage.run(%{"prompt" => "  "}, @ctx)
    assert {:error, _} = DrawImage.run(%{"prompt" => "x", "size" => "huge"}, @ctx)
    refute_received {:generate, _, _, _}
  end

  test "a refusal from the image model reaches the model in its own words" do
    Process.put(
      :image_reply,
      {:error,
       Request.exception(
         reason: "HTTP 400: Request failed",
         status: 400,
         response_body: %{
           "error" => %{"message" => "Your request was rejected by the safety system."}
         }
       )}
    )

    assert DrawImage.run(%{"prompt" => "x"}, @ctx) ==
             {:error, "The drawing failed: Your request was rejected by the safety system."}
  end
end
