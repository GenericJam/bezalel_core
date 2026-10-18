defmodule Bezalel.Materials.Material do
  @moduledoc """
  One material: a file sent to the agent, received from it, or derived
  from another material (`Bezalel.Materials`).

    * `id`: the SHA-256 of its bytes, lowercase hex. The same bytes are the
      same material, wherever they came from.
    * `kind`: `:image`, `:audio`, `:video`, `:document` or `:transcript`
      (text: what's said in an audio or video, or a document's text). A
      still and a generated picture are images (`derivation` says which).
    * `mime`, `name` (what the user calls it), `size` (bytes).
    * `source`: `:sent` (the user gave it), `:received` (the agent made or
      returned it: a drawing) or `:derived` (Bezalel made it from another:
      a transcript, an audio track, a still).
    * `derivation`: nil for an original, else `:transcript`,
      `:audio_track`, `:still` or `:generated`; `derived_from` the ids it
      was made from (a drawing's reference pictures; `[]` for a drawing
      from words alone).
    * `meta`: what's known about it, atom keys: `:duration_ms`, `:width`,
      `:height`, `:pages`, `:at_ms` (a still's time in its video),
      `:prompt` and `:model` (a drawing's).
    * `inserted_at`: when it was made (UTC).
  """

  @type kind :: :image | :audio | :video | :document | :transcript
  @type source :: :sent | :received | :derived
  @type derivation :: :transcript | :audio_track | :still | :generated

  @type t :: %__MODULE__{
          id: String.t(),
          kind: kind(),
          mime: String.t(),
          name: String.t(),
          size: non_neg_integer(),
          source: source(),
          derivation: derivation() | nil,
          derived_from: [String.t()],
          meta: map(),
          inserted_at: DateTime.t()
        }

  @enforce_keys [:id, :kind, :mime, :name, :size, :source, :inserted_at]
  defstruct [
    :id,
    :kind,
    :mime,
    :name,
    :size,
    :source,
    :inserted_at,
    derivation: nil,
    derived_from: [],
    meta: %{}
  ]
end
