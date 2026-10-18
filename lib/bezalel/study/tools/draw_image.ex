defmodule Bezalel.Study.Tools.DrawImage do
  @moduledoc """
  `draw_image`: a picture drawn for the user by the image model they chose
  in Settings ("Pictures by", `Bezalel.Study.Preferences`' `image_model`,
  one of `models/0`): OpenAI's gpt-image or a Gemini image model, through
  `ReqLLM.generate_image/3`, billed to that provider's API key, which the
  user added in Settings (`Rho.Auth`: `:openai`, `:google`). With a
  reference picture (a material's id: a photo the user sent, a still, an
  earlier drawing) gpt-image goes to the edits endpoint and Gemini gets
  the picture with the words; either draws from that picture.

  The drawing is kept as a material through the host's store
  (`Bezalel.Materials.put/3`: received, derivation `:generated`,
  `derived_from` its reference) and returned to rho by reference
  (`{:ok, {:images, [%{ref, mime, name}], text}}`), so the chat shows it from
  the store and the session holds no bytes. The model reads the drawing's
  ref in the text, to draw from it again.

  Not a study tool: it reads no pack and has no source to switch off, so
  it is in `Bezalel.Study.Tools.materials/0`, not `all/0`; a host offers it
  once it has a materials store. Without the chosen provider's API key it
  says which key is missing, for the model to tell the user where to add
  it (or to choose another image model).

  Config (`config :bezalel_core, :draw_image, ...`), for tests:
  `:generate` (`{m, f}` called as `ReqLLM.generate_image/3` is) and
  `:credential` (`{m, f}` called as `Rho.Auth.credential/1` is).
  """
  @behaviour Rho.Tool

  alias Bezalel.Materials
  alias Bezalel.Materials.Material
  alias Bezalel.Study.Preferences
  alias ReqLLM.Message.ContentPart

  @models [
    %{id: "openai:gpt-image-2", label: "OpenAI gpt-image-2", provider: :openai},
    %{id: "google:gemini-3.1-flash-image", label: "Gemini 3.1 Flash Image", provider: :google},
    %{id: "google:gemini-3-pro-image", label: "Gemini 3 Pro Image", provider: :google}
  ]

  @default_model "openai:gpt-image-2"

  # Each shape as OpenAI's size and as Gemini's aspect ratio.
  @sizes %{
    "square" => {"1024x1024", "1:1"},
    "landscape" => {"1536x1024", "3:2"},
    "portrait" => {"1024x1536", "2:3"}
  }

  @edit_types ["image/jpeg", "image/png", "image/webp"]

  @keys %{openai: "an OpenAI API key", google: "a Gemini API key"}
  @key_settings %{openai: "OpenAI, API key", google: "Gemini, API key"}

  @doc """
  The image models a user can choose ("Pictures by"), in the order a
  picker lists them: `%{id, label, provider}`, `id` a req_llm model spec,
  `provider` the `Rho.Auth` provider whose API key pays for the drawing.
  """
  @spec models() :: [%{id: String.t(), label: String.t(), provider: :openai | :google}]
  def models, do: @models

  @doc "The ids of `models/0`."
  @spec model_ids() :: [String.t()]
  def model_ids, do: Enum.map(@models, & &1.id)

  @doc "The image model a user who hasn't chosen one draws with: OpenAI's gpt-image."
  @spec default_model() :: String.t()
  def default_model, do: @default_model

  @impl true
  def name, do: "draw_image"

  @impl true
  def description do
    """
    Draw a picture for the user with the image model they chose in Settings, billed to their API key for that provider: a scene, a diagram, a map, an illustration of a passage. Describe it fully in `prompt`: the subject, what to show, the style, any words to letter in it. To draw from a picture (change it, or keep its look), give its ref in `references`: the ref of a picture the user attached (the ref attribute of its attachment) or of an earlier drawing. The user sees the drawing in the chat and it is kept in their Materials; you get its ref back. Draw when the user asks for a picture, or one plainly helps.\
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
  def run(args, ctx), do: run(args, ctx, Preferences.current(ctx))

  @doc """
  `run/2` with the user's settings given (`prefs.image_model` draws), as
  the host's `:preferences` hook would give them.
  """
  @spec run(map(), map(), Preferences.t()) :: {:ok, term()} | {:error, String.t()}
  def run(args, ctx, prefs) do
    model = Enum.find(@models, &(&1.id == prefs.image_model)) || hd(@models)

    with {:ok, prompt} <- prompt(args),
         {:ok, size} <- size(args),
         {:ok, _store} <- store(),
         {:ok, refs} <- references(args, ctx),
         {:ok, key} <- api_key(model),
         {:ok, {mime, bytes}} <- draw(model, prompt, size, refs, key) do
      material =
        Materials.derive(:generated, Enum.map(refs, &elem(&1, 0)), bytes,
          mime: mime,
          name: drawing_name(prompt, mime),
          meta: %{prompt: prompt, model: model.id}
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

  defp api_key(%{provider: provider, label: label}) do
    {m, f} = config(:credential, {Rho.Auth, :credential})

    case apply(m, f, [provider]) do
      {:ok, %{type: :api_key, key: key}} when is_binary(key) and key != "" ->
        {:ok, key}

      _ ->
        {:error,
         "Drawing a picture with #{label} (the image model chosen in Settings, Pictures by) " <>
           "needs #{@keys[provider]}, and none is set. Tell the user to add one in Settings " <>
           "(#{@key_settings[provider]}), or to choose another image model under Pictures by; " <>
           "drawings are billed to that key."}
    end
  end

  defp draw(model, prompt, {size, ratio}, refs, key) do
    {m, f} = config(:generate, {ReqLLM, :generate_image})
    {input, opts} = request(model.provider, prompt, size, ratio, refs, key)

    case apply(m, f, [model.id, input, opts]) do
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

  # gpt-image: the words, and a reference goes to the edits endpoint.
  defp request(:openai, prompt, size, _ratio, refs, key) do
    opts =
      case refs do
        [] -> []
        [{_material, {mime, bytes}}] -> [source_image: bytes, source_image_media_type: mime]
      end

    {prompt, [api_key: key, size: size, output_format: :jpeg] ++ opts}
  end

  # Gemini: one user message, the reference picture after the words; a
  # picture only, at the shape's aspect ratio. (req_llm's Google image
  # request takes the key as its `key` query parameter.)
  defp request(:google, prompt, _size, ratio, refs, key) do
    parts = [
      ContentPart.text(prompt)
      | for({_m, {mime, bytes}} <- refs, do: ContentPart.image(bytes, mime))
    ]

    input =
      if refs == [], do: prompt, else: ReqLLM.Context.new([ReqLLM.Context.user(parts)])

    {input,
     [api_key: key, aspect_ratio: ratio, provider_options: [response_modalities: ["IMAGE"]]]}
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

  defp config(key, default),
    do: :bezalel_core |> Application.get_env(:draw_image, []) |> Keyword.get(key, default)
end
