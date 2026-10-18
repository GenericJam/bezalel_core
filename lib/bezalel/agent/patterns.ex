defmodule Bezalel.Agent.Patterns do
  @moduledoc """
  The regular expressions the live agent's replies and passage cards use
  (`Bezalel.Agent.Reply`, `Bezalel.Agent.Card`), compiled on first use and
  kept in `:persistent_term`, as `Bezalel.Study.Patterns` keeps the study
  tools'. They are not `~r` literals: a regex compiled into a module is
  tied to the OTP it was compiled under, and a host app may be built on
  one OTP and run on another (mob_dev builds the phone app that way).
  """

  @sources %{
    # Bezalel.Agent.Card: punctuation and quotes around an English word.
    word_edges: {~S"^[\p{P}\p{S}]+|[\p{P}\p{S}]+$", "u"},
    # Bezalel.Agent.Reply: a block's header, its first sentence or line.
    first_sentence: {~S"\A.+?(?:[.?!:](?=\s)|\n|\z)", "su"},
    # Bezalel.Agent.Reply: a Markdown line that is a block of its own (a
    # heading, a list item, a quote, a table row, a fence) ...
    md_block_line: {~S"^ {0,3}(?:#{1,6}(?:\s|$)|[-*+]\s|[0-9]{1,9}[.)]\s|>|\||```|~~~)", "u"},
    # ... the marks that open it (nested: "> - [ ] item") ...
    md_block_mark:
      {~S"^(?:\s*(?:#{1,6}(?:\s+|$)|[-*+]\s+(?:\[[ xX]\]\s+)?|[0-9]{1,9}[.)]\s+|>\s?))+", "u"},
    # ... and a link or image, its text kept.
    md_link: {~S"!?\[([^\]]*)\]\([^)]*\)", "u"},
    # ... and an underscore that can open or close emphasis (not one inside
    # a word, as in lookup_verse).
    md_underscore: {~S"(?<![\p{L}\p{N}])_|_(?![\p{L}\p{N}])", "u"},
    # Bezalel.Speech: a heading, a list item, a table's separator row, a
    # thematic break ...
    heading: {~S"^ {0,3}#{1,6}(?:\s|$)", "u"},
    list_item: {~S"^\s*(?:[-*+]|[0-9]{1,9}[.)])\s", "u"},
    md_table_rule: {~S"^\|?\s*:?-{2,}:?\s*(?:\|\s*:?-{2,}:?\s*)*\|?\s*$", "u"},
    md_break: {~S"^ {0,3}([-*_])(?:\s*\1){2,}\s*$", "u"},
    # ... an image, an autolink, a bare URL, a footnote mark, an HTML tag ...
    md_image: {~S"!\[([^\]]*)\]\([^)]*\)", "u"},
    md_autolink: {~S"<(?:https?://|www\.)[^>]*>", "iu"},
    url: {~S{(?:https?://|www\.)[^\s<>()\[\]]*[^\s<>()\[\].,;:!?'"]}, "iu"},
    md_footnote: {~S"\[\^[^\]]*\]", "u"},
    html_tag: {~S"</?[a-zA-Z][^>]*>", "u"},
    # ... a run of Hebrew or Greek words (possessive, so a long run of
    # spaces or commas after one is scanned once), with the parenthesis
    # after it (where the model puts a transliteration: "רוּחַ (ruach)") ...
    original_run:
      {~S"[\x{0590}-\x{05FF}\x{FB1D}-\x{FB4F}\x{0370}-\x{03FF}\x{1F00}-\x{1FFF}]" <>
         ~S"[\x{0590}-\x{05FF}\x{FB1D}-\x{FB4F}\x{0370}-\x{03FF}\x{1F00}-\x{1FFF}\p{M}]*+" <>
         ~S"(?:[\s'’·,.;:]++[\x{0590}-\x{05FF}\x{FB1D}-\x{FB4F}\x{0370}-\x{03FF}\x{1F00}-\x{1FFF}]" <>
         ~S"[\x{0590}-\x{05FF}\x{FB1D}-\x{FB4F}\x{0370}-\x{03FF}\x{1F00}-\x{1FFF}\p{M}]*+)*+" <>
         ~S"(?:[*_]{0,3}\s*\((?<tr>[^()]*)\))?", "u"},
    original_char:
      {~S"[\x{0590}-\x{05FF}\x{FB1D}-\x{FB4F}\x{0370}-\x{03FF}\x{1F00}-\x{1FFF}]", "u"},
    marks: {~S"\p{M}", "u"},
    # ... a Strong's number in parentheses, punctuation an emptied
    # parenthesis leaves ...
    strongs_paren: {~S"\s*\((?:Strong'?s\s*)?[HG][0-9]{1,5}[A-Za-z]?\)", "u"},
    paren_open_punct: {~S"\(\s*[,;:]\s*", "u"},
    paren_close_punct: {~S"\s*[,;:]\s*\)", "u"},
    empty_paren: {~S"\s*\(\s*\)", "u"},
    space_before_punct: {~S"\s+([,.;:!?)])", "u"},
    # ... pauses doubled, or left before a stop ("the Word: ." once the
    # Greek is gone; from the first of a run only, so a long run is scanned
    # once) ...
    pause_run: {~S"(?<![,;:])([,;:])[,;:]++", "u"},
    punct_run: {~S"(?<![,;:])[,;:]++([.!?])", "u"},
    # ... a verse reference ("Ex 31:3", "1 Cor 13:4-7", "Luke 19:45-20:2"),
    # "v." / "vv." before a number, a range after "verses".
    speech_reference:
      {~S"(?<![\p{L}\p{N}])(?<book>(?:[1-4]\s?)?[A-Z][a-z]+\.?(?:\s+(?:of\s+|and\s+the\s+)?[A-Z][a-z]+\.?){0,3})" <>
         ~S"\s*(?<c1>[0-9]{1,3}):(?<v1>[0-9]{1,3})[a-z]?" <>
         ~S"(?:\s*[-\x{2010}-\x{2015}]\s*(?:(?<c2>[0-9]{1,3}):)?(?<v2>[0-9]{1,3})[a-z]?)?(?![0-9:])",
       "u"},
    verse_abbreviation: {~S"(?<![\p{L}])(vv?)\.\s*(?=[0-9])", "u"},
    verse_range: {~S"\b(verses\s+[0-9]+)\s*[-\x{2010}-\x{2015}]\s*([0-9]+)", "u"},
    speech_ending: {~S{[.!?…:;]["'”’)]*$}, "u"}
  }

  # The cache key carries a hash of the sources, so a hot-loaded version of
  # this module with a changed pattern compiles it afresh instead of reading
  # the old one out of :persistent_term.
  @version :erlang.phash2(@sources)

  @doc "The compiled pattern `name`."
  @spec get(atom()) :: Regex.t()
  def get(name) do
    key = {__MODULE__, @version, name}

    case :persistent_term.get(key, nil) do
      nil ->
        {source, options} = Map.fetch!(@sources, name)
        regex = Regex.compile!(source, options)
        :persistent_term.put(key, regex)
        regex

      regex ->
        regex
    end
  end
end
