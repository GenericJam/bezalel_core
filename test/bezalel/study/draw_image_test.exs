defmodule Bezalel.Study.DrawImageTest do
  # Configures :bezalel_core, :draw_image and :materials.
  use ExUnit.Case, async: false

  alias Bezalel.Materials
  alias Bezalel.Study.Tools
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

    def key(:openai), do: {:ok, %{type: :api_key, key: "sk-test"}}
    def signed_out(:openai), do: {:error, :signed_out}
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
      credential: credential,
      model: "openai:gpt-image-2"
    )
  end

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
    assert opts[:api_key] == "sk-test"
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
    assert message =~ "Settings"
    refute_received {:generate, _, _, _}
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
