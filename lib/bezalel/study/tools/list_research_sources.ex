defmodule Bezalel.Study.Tools.ListResearchSources do
  @moduledoc """
  `list_research_sources`: open journals, libraries and text archives to
  look in beyond the packs, from studybible-mcp's curated catalogue
  (`priv/study/research_sources.json`, their `research_sources.json` at
  commit 38cef28, MIT), compiled into this module. It needs no pack.

  Ported from studybible-mcp's `handle_list_research_sources`,
  `find_research_sources`, `_topic_score`, `_normalise_topic`,
  `research_search_url` and `format_research_sources` (`tools.py`, MIT).
  Same text. A `limit` that isn't a whole number is the default (theirs
  truncated 2.5 to 2 and failed on text); zero is the default and the
  limit is held to 1–10, as theirs.
  """
  @behaviour Rho.Tool

  alias Bezalel.Study.{Args, Patterns, Preferences}

  # Read at compile time (mix links priv into the build before compiling),
  # so the device needs no priv file.
  @catalogue_path Application.app_dir(:bezalel_core, "priv/study/research_sources.json")
  @external_resource @catalogue_path
  @catalogue @catalogue_path |> File.read!() |> JSON.decode!()

  @max_limit 10

  # Topic words an agent is likely to use that differ from the catalogue's tags.
  @topic_aliases [
    {"dss", "dead sea scrolls"},
    {"qumran", "dead sea scrolls"},
    {"lxx", "septuagint"},
    {"patristic", "church fathers"},
    {"patristics", "church fathers"},
    {"talmud", "rabbinic"},
    {"midrash", "rabbinic"},
    {"mishnah", "rabbinic"},
    {"old testament", "hebrew bible"},
    {"tanakh", "hebrew bible"},
    {"pseudepigrapha", "second temple"},
    {"journal", "biblical studies articles"},
    {"journals", "biblical studies articles"},
    {"articles", "biblical studies articles"},
    {"ane", "ancient near east"},
    {"manuscripts", "textual criticism"}
  ]

  @disclaimer "*These are places to look, not endorsements. Each source is listed for what it " <>
                "holds, with its perspective stated so it can be weighed; check claims against " <>
                "the primary texts.*"

  @impl true
  def name, do: "list_research_sources"

  @impl true
  def description do
    """
    Find free, reliable places to look for scholarly articles, primary texts, and commentary beyond this server's data, before a general web search: open journals, digital libraries, and text archives covering other authors and traditions, church fathers, rabbinic texts, Dead Sea Scrolls, Septuagint studies, and public-domain books. Each listing gives coverage, perspective, and access terms; with a `query`, sources that support it get a ready-to-open search link. Places to look, not endorsements.\
    """
  end

  @impl true
  def parameter_schema do
    %{
      "type" => "object",
      "properties" => %{
        "topic" => %{
          "type" => "string",
          "description" =>
            "Coverage tag or source name, matched loosely (e.g. 'rabbinic', 'church fathers', " <>
              "'dead sea scrolls', 'septuagint')"
        },
        "query" => %{
          "type" => "string",
          "description" => "Search terms for each source's search link (e.g. 'Psalm 82')"
        },
        "perspective" => %{
          "type" => "string",
          "description" =>
            "Jewish, Catholic, Reformed, evangelical, academic, multi-tradition, or single-author"
        },
        "limit" => %{
          "type" => "integer",
          "description" =>
            "Maximum sources to return. Default: the user's setting (8 unless changed), at most #{@max_limit}"
        }
      }
    }
  end

  @impl true
  def run(args, ctx) do
    with {:ok, result} <- result(args, Preferences.current(ctx)), do: {:ok, render(result)}
  end

  @typedoc """
  A catalogue listing, as in the JSON: "key", "name", "url",
  "description", "coverage" (tags), "perspective", "access",
  "search_url_template" (with `{query}`, or nil), "last_verified" (ISO
  date); with a query, "search_url" (nil when the source has no search
  link).
  """
  @type source :: %{String.t() => term()}

  @type t :: %{
          topic: String.t() | nil,
          query: String.t() | nil,
          perspective: String.t() | nil,
          total: non_neg_integer(),
          sources: [source()]
        }

  @doc "The catalogue."
  @spec catalogue() :: [source()]
  def catalogue, do: @catalogue

  @doc "The listings matching `args`, under the host's current preferences."
  @spec result(map()) :: {:ok, t()}
  def result(args), do: result(args, Preferences.current())

  @doc """
  The listings matching `args`' perspective and topic (possibly none),
  strongest topic matches first, up to the limit (by default `prefs`'),
  with `total` the number matching.
  """
  @spec result(map(), Preferences.t()) :: {:ok, t()}
  def result(args, prefs) do
    topic = Args.optional(args, "topic")
    query = Args.optional(args, "query")
    perspective = Args.optional(args, "perspective")
    default = Preferences.limit(prefs, @max_limit)

    limit =
      case Args.integer(args, "limit", default) do
        {:ok, n} when n != 0 -> n |> min(@max_limit) |> max(1)
        _ -> default
      end

    matches = find(topic, perspective)

    sources =
      matches
      |> Enum.take(limit)
      |> Enum.map(fn source ->
        if query, do: Map.put(source, "search_url", search_url(source, query)), else: source
      end)

    {:ok,
     %{
       topic: topic,
       query: query,
       perspective: perspective,
       total: length(matches),
       sources: sources
     }}
  end

  @doc "The catalogue filtered by perspective and loosely by topic, strongest topic matches first."
  @spec find(String.t() | nil, String.t() | nil) :: [source()]
  def find(topic, perspective) do
    sources =
      case perspective && String.downcase(String.trim(perspective)) do
        wanted when wanted not in [nil, ""] ->
          Enum.filter(@catalogue, &String.contains?(String.downcase(&1["perspective"]), wanted))

        _ ->
          @catalogue
      end

    case normalise(topic || "") do
      "" ->
        sources

      normalised ->
        sources
        |> Enum.map(&{topic_score(&1, normalised), &1})
        |> Enum.filter(fn {score, _} -> score > 0 end)
        |> Enum.sort_by(fn {score, _} -> -score end)
        |> Enum.map(&elem(&1, 1))
    end
  end

  @doc "A source's search link for `query`, or nil when it has no search template."
  @spec search_url(source(), String.t()) :: String.t() | nil
  def search_url(source, query) do
    case source["search_url_template"] do
      template when template in [nil, ""] ->
        nil

      template ->
        String.replace(template, "{query}", URI.encode_www_form(String.trim(query)))
    end
  end

  defp normalise(text) do
    Patterns.get(:research_topic_strip)
    |> Regex.replace(String.downcase(text), " ")
    |> String.split()
    |> Enum.join(" ")
  end

  # 2: the topic names a coverage tag or the source; 1: every topic word
  # appears in them; 0: no match.
  defp topic_score(source, topic) do
    tags = Enum.map(source["coverage"], &String.downcase/1)
    names = normalise("#{source["name"]} #{String.replace(source["key"], "_", " ")}")
    # The topic is normalised: words of [a-z0-9] between single spaces.
    padded = " #{topic} "

    wanted =
      [
        topic
        | for({phrase, tag} <- @topic_aliases, String.contains?(padded, " #{phrase} "), do: tag)
      ]

    cond do
      Enum.any?(wanted, fn phrase ->
        Enum.any?(tags, &(String.contains?(&1, phrase) or String.contains?(phrase, &1))) or
            String.contains?(names, phrase)
      end) ->
        2

      all_words?(topic, Enum.join(tags, " ") <> " " <> names) ->
        1

      true ->
        0
    end
  end

  defp all_words?(topic, haystack) do
    words = topic |> String.split() |> Enum.filter(&(String.length(&1) > 2))
    words != [] and Enum.all?(words, &String.contains?(haystack, &1))
  end

  @doc "The Markdown the model reads for a `result/1`."
  @spec render(t()) :: String.t()
  def render(result) do
    filters =
      for {label, value} <- [
            topic: result.topic,
            perspective: result.perspective,
            query: result.query
          ],
          value,
          do: "#{label}: #{value}"

    header =
      "## Research Sources" <> if(filters == [], do: "", else: " (#{Enum.join(filters, "; ")})")

    Enum.join([header, "", @disclaimer, ""] ++ body(result), "\n")
  end

  defp body(%{sources: []}) do
    perspectives = @catalogue |> Enum.map(& &1["perspective"]) |> Enum.uniq() |> Enum.sort()
    tags = @catalogue |> Enum.flat_map(& &1["coverage"]) |> Enum.uniq() |> Enum.sort()

    [
      "No sources match these filters.",
      "- Perspectives: #{Enum.join(perspectives, ", ")}",
      "- Coverage tags: #{Enum.join(tags, ", ")}"
    ]
  end

  defp body(%{sources: sources, total: total, query: query}) do
    shown =
      if total > length(sources),
        do: "Showing #{length(sources)} of #{total} matching sources.",
        else: "#{total} matching sources."

    listings =
      Enum.flat_map(sources, fn source ->
        search =
          cond do
            query == nil -> []
            source["search_url"] -> ["- **Search**: #{source["search_url"]}"]
            true -> ["- **Search**: no linkable search; browse or use the site's own search"]
          end

        [
          "### #{source["name"]}",
          source["url"],
          source["description"],
          "- **Coverage**: #{Enum.join(source["coverage"], ", ")}",
          "- **Perspective**: #{source["perspective"]}",
          "- **Access**: #{source["access"]}"
        ] ++ search ++ [""]
      end)

    oldest = sources |> Enum.map(& &1["last_verified"]) |> Enum.min()
    [shown, ""] ++ listings ++ ["*Listings verified on or after #{oldest}.*"]
  end
end
