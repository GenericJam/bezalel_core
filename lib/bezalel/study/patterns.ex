defmodule Bezalel.Study.Patterns do
  @moduledoc """
  The regular expressions the study tools use, compiled on first use and
  kept in `:persistent_term`. They are not `~r` literals: a regex compiled
  into a module is tied to the OTP it was compiled under, and mob_dev builds
  the phone app on one OTP for phones running another.

  The sources are studybible-mcp's (`database.py`, `hermeneutics.py`,
  `tools.py`), with Python's `(?P<name>…)` written `(?<name>…)`.
  """

  # The reference patterns spell digits [0-9]: with "u" (needed for the
  # dashes), \d would also match other scripts' digits, which
  # String.to_integer/1 rejects.
  @sources %{
    # parse_passage_reference: "Luke 19", "Luke 19:1-3", "Luke 19:45-20:2", "Psalm 23-24".
    passage:
      {~S"^(?<book>[1-4]?\s*[A-Za-z]+(?:\s+[A-Za-z]+)*)\s*\.?\s*(?<c1>[0-9]+)(?:[:.](?<v1>[0-9]+)[a-z]?)?" <>
         ~S"(?:\s*-\s*(?:(?<c2>[0-9]+)[:.])?(?<v2>[0-9]+)[a-z]?)?$", "iu"},
    # A range separator: hyphen, the Unicode dashes, minus.
    dash: {~S"\s*[\x{2010}-\x{2015}\x{2212}-]\s*", "u"},
    # _normalize_reference: "John 3:16", "Gen. 15:6", "1 Corinthians 13:4-7".
    verse:
      {~S"^([0-9]?\s*[a-zA-Z]+(?:\s+[a-zA-Z]+)*)\.?\s*([0-9]+):([0-9]+[a-z]?)(?:-([0-9]+[a-z]?))?$",
       "iu"},
    # expand_single_chapter_reference: "Jude 3", "Philemon 4-6", "Jude".
    single_chapter:
      {~S"^\s*(?<book>(?:[1-4]\s*)?[A-Za-z]+(?:\s+[A-Za-z]+)*)\.?" <>
         ~S"(?:\s*(?<verses>[0-9]+[a-z]?(?:\s*[-\x{2010}-\x{2015}\x{2212}]\s*[0-9]+[a-z]?)?))?\s*$",
       "u"},
    whitespace: {~S"\s+", "u"},
    leading_digit: {~S"^([0-9])\s*", "u"},
    strongs: {~S"^([GH])0*(\d{1,4})([A-Z]?)$", ""},
    strongs_bare: {~S"^[GH]\d{4}$", ""},
    strongs_suffixed: {~S"^[GH]\d{4}[A-Z]$", ""},
    # A verse stored with a second numbering: 'Gen.32.1(32.2)', 'Mat.17.15[17.14]'.
    split_reference: {~S"^([^.]+)\.(\d+)\.(\d+)([(\[{])(\d+)\.(\d+)[)\]}]$", ""},
    # A Psalm superscription: 'Psa.82.0(82.1)'.
    superscription: {~S"^([^.]+)\.(\d+)\.0(?:\((\d+\.\d+)\))?$", ""},
    # get_genre_from_reference: 'Jhn.3.16', then 'John 3:16'.
    genre_code: {~S"^(\w{3})\.\d+\.\d+", "u"},
    genre_name: {~S"^(\d?\s*[a-zA-Z]+)\s*\d+:\d+", "u"},
    # Ancient sources (database.py, tools.py, server.py, corpora/*.py).
    # parse_passage_reference's _PASSAGE_RE, for parse_biblical_range.
    biblical_range:
      {~S"^(?<book>[0-9]?\s*[a-z]+(?:\s+[a-z]+)*)\s*(?<c1>[0-9]+)(?::(?<v1>[0-9]+)(?<s1>[a-z]?))?" <>
         ~S"(?:\s*[-–—]\s*(?:(?<c2>[0-9]+):)?(?<v2>[0-9]+)(?<s2>[a-z]?))?$", "iu"},
    ancient_word: {~S"\w+", "u"},
    ancient_marks: {~S"[\p{Mn}\p{Cf}]", "u"},
    ancient_combining: {~S"\p{M}", "u"},
    editorial_signs: {~S"[\[\]⟨⟩〈〉<>{}()^¦]", "u"},
    hebrew_word: {~S"^[\x{05d0}-\x{05ea}]+$", "u"},
    original_script: {~S"[\x{0370}-\x{03ff}\x{1f00}-\x{1fff}\x{0590}-\x{05ff}]", "u"},
    nc_license: {~S"CC BY-NC(-SA)? (\d\.\d)", ""},
    trailing_locator: {~S"[\s.,]+[0-9ivxlc][0-9ivxlc\s.:,\-–]*$", "iu"},
    name_token: {~S"[^\W_]+", "u"},
    citation_skip: {~S"^[\s.,]*", "u"},
    apostrophes: {~S"['’ʼ]", "u"},
    locator_dash: {~S"\s*[-‐‑‒–—]\s*", "u"},
    locator_separator: {~S"\s*[.:,]\s*|\s+", "u"},
    locator_trailing: {~S"[\s.;,]+$", "u"},
    roman: {~S"^(?=[mdclxvi])m{0,3}(cm|cd|d?c{0,3})(xc|xl|l?x{0,3})(ix|iv|v?i{0,3})$", "iu"},
    ascii_digits: {~S"^[0-9]+$", ""},
    locator_strip_left: {~S"\A[ .,]+", ""},
    locator_strip_right: {~S"[ .,]+\z", ""},
    line_breaks: {~S"\r\n|[\n\r\x{0b}\x{0c}\x{1c}-\x{1e}\x{85}\x{2028}\x{2029}]", "u"},
    # get_textual_variant: a normalized single verse ('Psa.40.6', '1Ki.2.35a').
    single_verse_reference: {~S"^[1-3]?[A-Za-z]{2,3}\.[0-9]+\.[0-9]+[a-z]?$", ""},
    # A not-preserved witness's "(none preserved)" suffix.
    none_preserved: {~S"\s*\(none preserved\)\s*$", "iu"},
    # compare_biblical_versions: a MT verse's Hebrew numbering, 'Psa.82.0(82.1)'.
    hebrew_numbering: {~S"\(([0-9]+)\.([0-9]+)\)$", ""},
    # A comparison reference's book, for the continuation note (server.py _REFERENCE_BOOK).
    reference_book:
      {~S"^\s*(.*?\D)\s*\d+(?:\s*:\s*\d+)?(?:\s*[-–—]\s*\d+(?:\s*:\s*\d+)?)?\s*$", "u"},
    # get_ane_context: an ANE entry's key reference's book and chapter
    # ('Gen 38:6-26', '1 Cor 12:12'; server.py _KEY_REF_PATTERN).
    ane_key_reference: {~S"^(\d?\s*[A-Za-z]+)\s+(\d+)", ""},
    # list_research_sources: what a topic loses before matching (_normalise_topic).
    research_topic_strip: {~S"[^a-z0-9\s]", "u"}
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
