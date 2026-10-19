defmodule Bezalel.Study.Tools.DrawImage do
  @moduledoc """
  `draw_image`: a picture drawn for the user by one of `models/0`:
  ChatGPT on the user's ChatGPT sign-in (`Rho.Images.generate/2`, Codex's
  hosted image tool, counted against their ChatGPT plan, no API key), or
  OpenAI's gpt-image or a Gemini image model through
  `ReqLLM.generate_image/3`, billed to that provider's API key, which the
  user added in Settings (`Rho.Auth`: `:openai_codex`, `:openai`,
  `:google`). With a reference picture (a material's id: a photo the user
  sent, a still, an earlier drawing) each draws from that picture: ChatGPT
  gets it with the words, gpt-image goes to the edits endpoint, Gemini
  gets it with the words.

  Which model draws (`model/2`), first that applies:

    1. the call's `model` argument: the lead names one when the user asks
       for it ("have ChatGPT draw it", "get Gemini to draw");
    2. the one the user chose in Settings ("Pictures by",
       `Bezalel.Study.Preferences`' `image_model`);
    3. unchosen (nil): `automatic_model/0`, the first of `models/0` whose
       provider is signed in (ChatGPT, then an OpenAI key, then a Gemini
       key), else OpenAI's gpt-image, whose missing key the tool reports.

  An explicit choice is never overridden by what's signed in: without its
  credential the tool says which sign-in or key is missing, for the model
  to tell the user where to add it (or to choose another image model).

  The drawing is kept as a material through the host's store
  (`Bezalel.Materials.put/3`: received, derivation `:generated`,
  `derived_from` its reference) and returned to rho by reference
  (`{:ok, {:images, [%{ref, mime, name}], text}}`), so the chat shows it from
  the store and the session holds no bytes. The model reads the drawing's
  ref in the text, to draw from it again.

  Not a study tool: it reads no pack and has no source to switch off, so
  it is in `Bezalel.Study.Tools.materials/0`, not `all/0`; a host offers it
  once it has a materials store.

  Config (`config :bezalel_core, :draw_image, ...`), for tests:
  `:generate` (`{m, f}` called as `ReqLLM.generate_image/3` is),
  `:images` (`{m, f}` called as `Rho.Images.generate/2` is),
  `:credential` (`{m, f}` called as `Rho.Auth.credential/1` is) and
  `:signed_in` (`{m, f}` called as `Rho.Auth.signed_in?/1` is).
  """
  @behaviour Rho.Tool

  alias Bezalel.Materials
  alias Bezalel.Materials.Material
  alias Bezalel.Study.Preferences
  alias ReqLLM.Message.ContentPart

  @models [
    %{id: "openai_codex:gpt-image", label: "ChatGPT (your sign-in)", provider: :openai_codex},
    %{id: "openai:gpt-image-2", label: "OpenAI gpt-image-2", provider: :openai},
    %{id: "google:gemini-3.1-flash-image", label: "Gemini 3.1 Flash Image", provider: :google},
    %{id: "google:gemini-3-pro-image", label: "Gemini 3 Pro Image", provider: :google}
  ]

  @fallback_model "openai:gpt-image-2"

  # Each shape as OpenAI's size and as Gemini's aspect ratio.
  @sizes %{
    "square" => {"1024x1024", "1:1"},
    "landscape" => {"1536x1024", "3:2"},
    "portrait" => {"1024x1536", "2:3"}
  }

  @edit_types ["image/jpeg", "image/png", "image/webp"]

  @needs %{
    openai_codex: "a ChatGPT sign-in",
    openai: "an OpenAI API key",
    google: "a Gemini API key"
  }
  @where %{
    openai_codex: "sign in with ChatGPT in Settings (ChatGPT, Sign in)",
    openai: "add one in Settings (OpenAI, API key)",
    google: "add one in Settings (Gemini, API key)"
  }
  @billing %{
    openai_codex: "drawings count against their ChatGPT plan",
    openai: "drawings are billed to that key",
    google: "drawings are billed to that key"
  }

  @doc """
  The image models a user can choose ("Pictures by"), in the order a
  picker lists them: `%{id, label, provider}`, `id` a model spec,
  `provider` the `Rho.Auth` provider whose sign-in or API key draws.
  """
  @spec models() :: [
          %{id: String.t(), label: String.t(), provider: :openai_codex | :openai | :google}
        ]
  def models, do: @models

  @doc "The ids of `models/0`."
  @spec model_ids() :: [String.t()]
  def model_ids, do: Enum.map(@models, & &1.id)

  @doc """
  The model a user who hasn't chosen one draws with: the first of
  `models/0` whose provider is signed in (`Rho.Auth.signed_in?/1`), so the
  ChatGPT sign-in when there is one; else OpenAI's gpt-image.
  """
  @spec automatic_model() :: map()
  def automatic_model do
    {m, f} = config(:signed_in, {Rho.Auth, :signed_in?})

    Enum.find(@models, &apply(m, f, [&1.provider])) ||
      Enum.find(@models, &(&1.id == @fallback_model))
  end

  @doc """
  The model that draws for `prefs` (a `model` argument, `requested`, first;
  see the moduledoc): one of `models/0`. A host's Settings shows
  `model(prefs)` as the Pictures by in effect.
  """
  @spec model(Preferences.t(), String.t() | nil) :: map()
  def model(prefs, requested \\ nil) do
    Enum.find(@models, &(&1.id == requested)) ||
      Enum.find(@models, &(&1.id == prefs.image_model)) ||
      automatic_model()
  end

  @impl true
  def name, do: "draw_image"

  @impl true
  def description do
    """
    Draw a picture for the user: a scene, a diagram, a map, an illustration of a passage. Describe it fully in `prompt`: the subject, what to show, the style, any words to letter in it. To draw from a picture (change it, or keep its look), give its ref in `references`: the ref of a picture the user attached (the ref attribute of its attachment) or of an earlier drawing. It draws with the image model the user chose in Settings; when the user asks for a particular one to draw ("have ChatGPT draw…", "get Gemini to draw…"), name it in `model`: openai_codex:gpt-image is ChatGPT on the user's ChatGPT sign-in, openai:gpt-image-2 is OpenAI on their API key, google:… are Gemini on their Gemini key. Another model's drawing comes only through this tool, never ask_model, which answers in words. The user sees the drawing in the chat and it is kept in their Materials; you get its ref back. Draw when the user asks for a picture, or one plainly helps.\
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
        },
        "model" => %{
          "type" => "string",
          "enum" => Enum.map(@models, & &1.id),
          "description" =>
            "Who draws, only when the user asks for one (optional; else their Settings choice)."
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
  `run/2` with the user's settings given (`prefs.image_model`, see
  `model/2`), as the host's `:preferences` hook would give them.
  """
  @spec run(map(), map(), Preferences.t()) :: {:ok, term()} | {:error, String.t()}
  def run(args, ctx, prefs) do
    with {:ok, prompt} <- prompt(args),
         {:ok, size} <- size(args),
         {:ok, requested} <- requested(args),
         model = model(prefs, requested),
         {:ok, _store} <- store(),
         {:ok, refs} <- references(args, ctx),
         {:ok, auth} <- credential(model, why(model, requested, prefs)),
         {:ok, {mime, bytes}} <- draw(model, prompt, size, refs, auth) do
      material =
        Materials.derive(:generated, Enum.map(refs, &elem(&1, 0)), bytes,
          mime: mime,
          name: drawing_name(prompt, mime),
          meta: %{prompt: prompt, model: model.id}
        )

      case Materials.put(material, bytes, ctx) do
        {:ok, kept} ->
          {:ok, {:images, [%{ref: kept.id, mime: kept.mime, name: kept.name}], text(kept, model)}}

        {:error, reason} ->
          {:error, "The picture was drawn but couldn't be kept: #{inspect(reason)}."}
      end
    end
  end

  defp requested(args) do
    case args["model"] do
      nil ->
        {:ok, nil}

      id when is_binary(id) ->
        if id in model_ids(),
          do: {:ok, id},
          else: {:error, "model is one of #{Enum.join(model_ids(), ", ")}, not #{inspect(id)}."}

      other ->
        {:error, "model is one of #{Enum.join(model_ids(), ", ")}, not #{inspect(other)}."}
    end
  end

  # Why this model draws, for a missing credential's message.
  defp why(%{id: id}, id, _prefs), do: "asked for in `model`"
  defp why(%{id: id}, _requested, %{image_model: id}), do: "the image model chosen in Settings"
  defp why(_model, _requested, _prefs), do: "the default: none is chosen in Settings"

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

  defp credential(%{provider: provider, label: label}, why) do
    {m, f} = config(:credential, {Rho.Auth, :credential})

    case {provider, apply(m, f, [provider])} do
      {:openai_codex, {:ok, %{type: :oauth}}} ->
        {:ok, fn p -> apply(m, f, [p]) end}

      {_api, {:ok, %{type: :api_key, key: key}}} when is_binary(key) and key != "" ->
        {:ok, key}

      {:openai_codex, {:error, {:refresh_failed, message}}} ->
        {:error,
         "The ChatGPT sign-in has expired (#{message}). Tell the user to sign in with " <>
           "ChatGPT again in Settings (ChatGPT, Sign in), or to choose another image model " <>
           "under Pictures by."}

      _ ->
        {:error,
         "Drawing a picture with #{label} (#{why}) needs #{@needs[provider]}, and there is " <>
           "none. Tell the user to #{@where[provider]}, or to choose another image model " <>
           "under Settings, Pictures by; #{@billing[provider]}."}
    end
  end

  # ChatGPT: the sign-in's Codex image tool, the reference with the words.
  defp draw(%{provider: :openai_codex}, prompt, {size, _ratio}, refs, credential) do
    {m, f} = config(:images, {Rho.Images, :generate})

    opts = [
      size: size,
      format: "jpeg",
      references: for({_material, picture} <- refs, do: picture),
      credential: credential
    ]

    case apply(m, f, [prompt, opts]) do
      {:ok, %{mime: mime, bytes: bytes}} -> {:ok, {mime, bytes}}
      {:error, error} -> {:error, "The drawing failed: #{Rho.LLM.describe(error)}"}
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

  defp text(%Material{} = m, model) do
    "Drew the picture with #{model.label}; the user sees it in the chat, kept in their " <>
      "Materials as #{inspect(m.name)} (ref #{m.id})."
  end

  defp config(key, default),
    do: :bezalel_core |> Application.get_env(:draw_image, []) |> Keyword.get(key, default)
end
