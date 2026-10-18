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
  host app's model id, or `"storyboard"`). `images` are the pictures in
  its entries (a tool's, a model's, a user's attachment), each
  `%{key, entry, index, mime}`: the `index`th image part of entry `entry`,
  `key` unique across sessions.
  """

  @type image :: %{key: String.t(), entry: String.t(), index: non_neg_integer(), mime: String.t()}

  @type t :: %__MODULE__{
          id: String.t(),
          role: :user | :agent,
          text: String.t() | nil,
          blocks: [map()],
          passage: String.t() | nil,
          card: map() | nil,
          image: String.t() | nil,
          images: [image()],
          model: String.t() | nil,
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
    blocks: [],
    images: [],
    entries: []
  ]
end
