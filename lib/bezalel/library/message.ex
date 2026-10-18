defmodule Bezalel.Library.Message do
  @moduledoc """
  A message as the chat shows it, read from the conversation's session
  (`Bezalel.Library.Transcript`): a user message, or an agent reply (every
  session entry between two user messages).

  `id` is the session id of its first entry and `entries` all of them (a
  delete takes them all). A user message has `text`. A reply has `blocks`
  (each `%{"id", "type", "first", "rest"}`, `"cut" => true` when `first`
  is cut short and `rest` holds the whole text: THINKING, TOOL CALL,
  SUMMARY), optionally a cited passage, as the host app's scripture key
  (`passage`, scripted replies) or a card built from the study tools'
  results (`card`, `Bezalel.Agent.Card`, live replies), a requested
  drawing's subject (`image`, scripted), the `model` that answered (the
  host app's model id, or `"storyboard"`), and the sources its tools
  consulted (`citations`, `Bezalel.Study.Citation`s in the order the tools
  returned them, each `cited` when the reply's text links it:
  `Bezalel.Agent.Reply.sources/1`; a sources list groups them with
  `Bezalel.Study.Citations.by_work/1`), and what its model calls used
  (`usage`, `Bezalel.Usage.reply_usage/1`: tokens and cost; nil for a reply
  no call reported tokens for).

  Its files come two ways. `materials` are those sent or received by
  reference (`Bezalel.Materials`: a user's attachment, a `draw_image`
  drawing), each `%{id, kind, mime, name, about, entry}`: the material's
  id (the host's store has it), its kind by its media type (`:image`,
  `:audio`, `:video`, `:document`: what the chat draws; a transcript sent
  on its own is a text document here, and the store has the material's
  own kind), and the session entry it is in. `images`
  are the pictures stored inline in its entries (a tool's, a model's, a
  user's attachment from before materials), each `%{key, entry, index,
  mime}`: the `index`th image part of entry `entry`, `key` unique across
  sessions.
  """

  @type image :: %{key: String.t(), entry: String.t(), index: non_neg_integer(), mime: String.t()}

  @type material :: %{
          id: String.t(),
          kind: :image | :audio | :video | :document,
          mime: String.t(),
          name: String.t(),
          about: String.t() | nil,
          entry: String.t() | nil
        }

  @type t :: %__MODULE__{
          id: String.t(),
          role: :user | :agent,
          text: String.t() | nil,
          blocks: [map()],
          passage: String.t() | nil,
          card: map() | nil,
          citations: [Bezalel.Study.Citation.t()],
          image: String.t() | nil,
          images: [image()],
          materials: [material()],
          model: String.t() | nil,
          usage: Bezalel.Usage.reply_usage() | nil,
          entries: [String.t()]
        }

  defstruct [
    :id,
    :role,
    :text,
    :passage,
    :card,
    :image,
    :model,
    :usage,
    blocks: [],
    citations: [],
    images: [],
    materials: [],
    entries: []
  ]
end
