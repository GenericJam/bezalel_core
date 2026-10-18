defmodule Bezalel.Materials.Store do
  @moduledoc """
  Where the host keeps materials: `config :bezalel_core, :materials,
  MyApp.MaterialStore`, a module with this behaviour. Core never decides
  where a file lives or who owns it; the store does.

  Every callback gets `ctx`, a map with `:session_id` (the rho session the
  material goes with or came from: a tool's ctx, rho's attachment
  resolver's, or the host's own when it sends a question; nil when there is
  none), so a host serving several users finds the owner from the
  conversation, and **answers only for that owner**: another user's
  material is not there. A store may read more keys of its own from a ctx
  it builds.

    * `c:put/3` keeps `material` with its `bytes` (the bytes' SHA-256 is
      `material.id`; `Bezalel.Materials.write_file/3` lays them out under a
      directory) for the ctx's owner and returns it as kept. Putting a
      material that is already there returns the kept one: the same bytes
      are the same material.
    * `c:fetch/2`: the material `id`, or `:error` when there is none (or
      it isn't the ctx's owner's).
    * `c:read/2`: its bytes, as kept (an error for another owner's).
    * `c:derivatives/2`: the owner's materials made from `id`
      (`derived_from` holds it): its transcripts, audio track, stills,
      drawings.
    * `c:for_model/2` (optional): the bytes to send a model for an image or
      PDF (`{mime, bytes}`), when the host resizes or re-encodes a picture
      first (a phone photo is larger than providers take). Without it, the
      model gets `c:read/2`'s bytes as they are.
  """

  alias Bezalel.Materials.Material

  @type ctx :: %{optional(:session_id) => String.t() | nil, optional(atom()) => term()}

  @callback put(material :: Material.t(), bytes :: binary(), ctx()) ::
              {:ok, Material.t()} | {:error, term()}
  @callback fetch(id :: String.t(), ctx()) :: {:ok, Material.t()} | :error
  @callback read(material :: Material.t(), ctx()) :: {:ok, binary()} | {:error, term()}
  @callback derivatives(id :: String.t(), ctx()) :: [Material.t()]
  @callback for_model(material :: Material.t(), ctx()) ::
              {:ok, {String.t(), binary()}} | {:error, term()}

  @optional_callbacks for_model: 2
end
