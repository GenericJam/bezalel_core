defmodule Bezalel.Study.Tools.DrawImage do
  @moduledoc """
  `draw_image`: a picture drawn for the user by OpenAI's image model
  (gpt-image, through `ReqLLM.generate_image/3`), billed to the OpenAI API
  key the user added in Settings (`Rho.Auth`, `:openai`). With a reference
  picture (a material's id: a photo the user sent, a still, an earlier
  drawing) it goes to the edits endpoint, which draws from that picture.

  The drawing is kept as a material through the host's store
  (`Bezalel.Materials.put/3`: received, derivation `:generated`,
  `derived_from` its reference) and returned to rho by reference
  (`{:ok, {:images, [%{ref, mime, name}], text}}`), so the chat shows it from
  the store and the session holds no bytes. The model reads the drawing's
  ref in the text, to draw from it again.

  Not a study tool: it reads no pack and has no source to switch off, so
  it is in `Bezalel.Study.Tools.materials/0`, not `all/0`; a host offers it
  once it has a materials store. Without an OpenAI API key it says so, for
  the model to tell the user where to add one.

  Config (`config :bezalel_core, :draw_image, ...`): `:model` (default
  `#{inspect("openai:gpt-image-2")}`), and for tests `:generate` (`{m, f}`
  called as `ReqLLM.generate_image/3` is) and `:credential` (`{m, f}`
  called as `Rho.Auth.credential/1` is).
  """
  @behaviour Rho.Tool

  alias Bezalel.Materials
  alias Bezalel.Materials.Material

  @default_model "openai:gpt-image-2"

  @sizes %{"square" => "1024x1024", "landscape" => "1536x1024", "portrait" => "1024x1536"}

  @edit_types ["image/jpeg", "image/png", "image/webp"]

  @no_key "Drawing a picture needs an OpenAI API key, and none is set. Tell the user to add " <>
            "one in Settings (OpenAI, API key); drawings are billed to that key."

  @impl true
  def name, do: "draw_image"

  @impl true
  def description do
    """
    Draw a picture for the user with OpenAI's image model, billed to the user's OpenAI API key: a scene, a diagram, a map, an illustration of a passage. Describe it fully in `prompt`: the subject, what to show, the style, any words to letter in it. To draw from a picture (change it, or keep its look), give its ref in `references`: the ref of a picture the user attached (the ref attribute of its attachment) or of an earlier drawing. The user sees the drawing in the chat and it is kept in their Materials; you get its ref back. Draw when the user asks for a picture, or one plainly helps.\
    """
  end

  @impl true
  def parameter_schema do
    %{
      "type" => "object",
      "properties" => %{
        "prompt" => %{
          "type" => "string",
          "description" => "What to draw, in full: subject, details, style, any lettering."
        },
        "references" => %{
          "type" => "array",
          "items" => %{"type" => "string"},
          "maxItems" => 1,
          "description" => "The ref of one picture to draw from (optional)."
        },
        "size" => %{
          "type" => "string",
          "enum" => Map.keys(@sizes),
          "description" => "The picture's shape: square (the default), landscape or portrait."
        }
      },
      "required" => ["prompt"]
    }
  end

  # A drawing takes a minute or more.
  @impl true
  def timeout_ms, do: 180_000

  @impl true
  def run(args, ctx) do
    with {:ok, prompt} <- prompt(args),
         {:ok, size} <- size(args),
         {:ok, _store} <- store(),
         {:ok, refs} <- references(args, ctx),
         {:ok, key} <- api_key(),
         {:ok, {mime, bytes}} <- draw(prompt, size, refs, key) do
      material =
        Materials.derive(:generated, Enum.map(refs, &elem(&1, 0)), bytes,
          mime: mime,
          name: drawing_name(prompt, mime),
          meta: %{prompt: prompt, model: model()}
        )

      case Materials.put(material, bytes, ctx) do
        {:ok, kept} ->
          {:ok, {:images, [%{ref: kept.id, mime: kept.mime, name: kept.name}], text(kept)}}

        {:error, reason} ->
          {:error, "The picture was drawn but couldn't be kept: #{inspect(reason)}."}
      end
    end
  end

  defp prompt(%{"prompt" => prompt}) when is_binary(prompt) do
    case String.trim(prompt) do
      "" -> {:error, "Say what to draw in `prompt`."}
      prompt -> {:ok, prompt}
    end
  end

  defp prompt(_args), do: {:error, "Say what to draw in `prompt`."}

  defp size(args) do
    case args["size"] do
      nil -> {:ok, @sizes["square"]}
      size when is_map_key(@sizes, size) -> {:ok, @sizes[size]}
      other -> {:error, "size is square, landscape or portrait, not #{inspect(other)}."}
    end
  end

  defp store do
    case Materials.store() do
      {:ok, store} ->
        {:ok, store}

      {:error, :no_store} ->
        {:error, "This app can't keep drawings yet, so draw_image can't run."}

      {:error, {:bad_store, store}} ->
        {:error,
         "This app's materials store (#{inspect(store)}) isn't working, so draw_image can't run."}
    end
  end

  # The reference pictures: `{material, {mime, bytes}}` each, the bytes as
  # the host sends a picture to a model. req_llm's edits form carries one.
  defp references(args, ctx) do
    case args["references"] || [] do
      [] ->
        {:ok, []}

      [id] when is_binary(id) ->
        with {:ok, material} <- reference(id, ctx),
             {:ok, picture} <- picture(material, ctx),
             do: {:ok, [{material, picture}]}

      [_, _ | _] ->
        {:error, "draw_image draws from one picture at a time; give one ref in `references`."}

      _other ->
        {:error, "`references` is a list with one picture's ref."}
    end
  end

  defp reference(id, ctx) do
    case Materials.fetch(id, ctx) do
      {:ok, %Material{kind: :image} = m} ->
        {:ok, m}

      {:ok, %Material{name: name}} ->
        {:error, "#{name} isn't a picture, so it can't be drawn from."}

      :error ->
        {:error, "There is no picture with ref #{inspect(id)} in this conversation."}
    end
  end

  # The edits endpoint takes JPEG, PNG and WebP: a HEIC photo goes only
  # through a store that converts it (`for_model/2`).
  defp picture(material, ctx) do
    case Materials.resolve(%{"ref" => material.id}, ctx) do
      {:ok, {mime, bytes}} when mime in @edit_types ->
        {:ok, {mime, bytes}}

      {:ok, {mime, _bytes}} ->
        {:error,
         "#{material.name} is #{mime}; the image model draws from JPEG, PNG or WebP only."}

      {:error, reason} ->
        {:error, "#{material.name} couldn't be read: #{inspect(reason)}."}
    end
  end

  defp api_key do
    {m, f} = config(:credential, {Rho.Auth, :credential})

    case apply(m, f, [:openai]) do
      {:ok, %{type: :api_key, key: key}} when is_binary(key) and key != "" -> {:ok, key}
      _ -> {:error, @no_key}
    end
  end

  defp draw(prompt, size, refs, key) do
    {m, f} = config(:generate, {ReqLLM, :generate_image})

    opts =
      case refs do
        [] -> []
        [{_material, {mime, bytes}}] -> [source_image: bytes, source_image_media_type: mime]
      end

    case apply(m, f, [model(), prompt, [api_key: key, size: size, output_format: :jpeg] ++ opts]) do
      {:ok, response} ->
        case Enum.find(
               ReqLLM.Response.images(response),
               &(&1.type == :image and is_binary(&1.data))
             ) do
          %{data: data, media_type: mime} -> {:ok, {mime || "image/jpeg", data}}
          nil -> {:error, "The image model answered without a picture."}
        end

      {:error, error} ->
        {:error, "The drawing failed: #{describe(error)}"}
    end
  end

  defp describe(%{response_body: %{"error" => %{"message" => message}}}) when is_binary(message),
    do: message

  defp describe(error) when is_exception(error), do: Exception.message(error)
  defp describe(error), do: inspect(error)

  defp drawing_name(prompt, mime) do
    words = prompt |> String.split() |> Enum.take(6) |> Enum.join(" ")
    words = if String.length(words) > 48, do: String.slice(words, 0, 48), else: words
    "Drawing – #{String.trim_trailing(words, ".")}.#{Materials.extension(mime)}"
  end

  defp text(%Material{} = m) do
    "Drew the picture; the user sees it in the chat, kept in their Materials as " <>
      "#{inspect(m.name)} (ref #{m.id})."
  end

  defp model, do: config(:model, @default_model)

  defp config(key, default),
    do: :bezalel_core |> Application.get_env(:draw_image, []) |> Keyword.get(key, default)
end
