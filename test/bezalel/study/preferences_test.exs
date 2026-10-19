defmodule Bezalel.Study.PreferencesTest do
  # The user's settings, the sources they can switch off, the tools that
  # are then withheld, and the system prompt built from them.
  use ExUnit.Case, async: true

  alias Bezalel.Study.{Preferences, Prompt, Sources, Tools, Translations}

  describe "Preferences.new/1" do
    test "the defaults: no approach, labels on, verdicts and genre guidance off, 8 results, the NET" do
      prefs = Preferences.new(%{})
      assert prefs == %Preferences{}
      assert prefs.approach == nil
      assert prefs.scripture_labels

      assert prefs.excluded_sources ==
               MapSet.new(["editorial:verdicts", "method:genre_guidance"])

      assert prefs.excluded_sources == MapSet.new(Sources.default_excluded())
      assert prefs.limit == 8
      assert prefs.translation == "net"
    end

    test "valid values are kept, from atom or string keys, a map or a keyword list" do
      prefs =
        Preferences.new(%{
          "approach" => "Write as a rabbi would.",
          "scripture_labels" => false,
          "excluded_sources" => ["ancient:philo", "ane:context"],
          "limit" => 12,
          "translation" => "bsb"
        })

      assert prefs.approach == "Write as a rabbi would."
      refute prefs.scripture_labels
      assert prefs.excluded_sources == MapSet.new(["ancient:philo", "ane:context"])
      assert prefs.limit == 12
      assert prefs.translation == "bsb"

      assert Preferences.new(limit: 3, excluded_sources: MapSet.new([])) ==
               %Preferences{limit: 3, excluded_sources: MapSet.new()}
    end

    test "invalid values fall back to the defaults; unknown keys and sources are dropped" do
      prefs =
        Preferences.new(%{
          approach: "   ",
          scripture_labels: "no",
          excluded_sources: ["ancient:philo", "made:up", 7],
          limit: 51,
          translation: "kjv",
          colour: "blue"
        })

      assert prefs.approach == nil
      assert prefs.scripture_labels
      assert prefs.excluded_sources == MapSet.new(["ancient:philo"])
      assert prefs.limit == 8
      assert prefs.translation == "net"

      assert Preferences.new(limit: 0).limit == 8
      assert Preferences.new(limit: 2.0).limit == 8
      assert Preferences.new(limit: 50).limit == 50

      assert Preferences.new(excluded_sources: "ane:context").excluded_sources ==
               %Preferences{}.excluded_sources
    end

    test "a struct is checked again" do
      assert Preferences.new(%Preferences{limit: 999}).limit == 8
    end

    test "Pictures by and Pushback from: none chosen by default; only known models" do
      assert %Preferences{}.image_model == nil
      assert %Preferences{}.pushback_model == nil

      prefs =
        Preferences.new(%{
          "image_model" => "openai_codex:gpt-image",
          "pushback_model" => "google:gemini-3-pro"
        })

      assert {prefs.image_model, prefs.pushback_model} ==
               {"openai_codex:gpt-image", "google:gemini-3-pro"}

      # An image model not offered (a chat model, an unknown one), a
      # pushback model rho can't call: none chosen.
      for image <- ["google:gemini-3-pro", "openai:dall-e-9", nil, 3],
          do: assert(Preferences.new(image_model: image).image_model == nil)

      for critic <- ["gemini-3-pro", "mistral:large", "", 3],
          do: assert(Preferences.new(pushback_model: critic).pushback_model == nil)
    end

    test "limit/2 holds the setting to a tool's maximum" do
      assert Preferences.limit(%Preferences{limit: 30}, 20) == 20
      assert Preferences.limit(%Preferences{limit: 5}, 20) == 5
      assert Preferences.limit(%Preferences{limit: 30}, nil) == 30
    end
  end

  describe "Sources" do
    test "one key per ancient corpus, theologian, note type and layer, with the default off" do
      keys = Sources.keys()

      for corpus <- ~w(josephus targum qumran philo pseudepigrapha rabbinic),
          do: assert("ancient:#{corpus}" in keys)

      for author <- ~w(heiser bradley owen stott lennox synthesis),
          do: assert("theology:#{author}" in keys)

      for key <-
            ~w(editorial:verdicts manuscripts:dss notes:study_notes notes:translation_notes_uw notes:translation_notes_sil notes:dictionary notes:key_terms ane:context crossrefs:themes method:torah_weave method:genre_guidance),
          do: assert(key in keys)

      assert keys == Enum.uniq(keys)
      assert Sources.default_excluded() == ["editorial:verdicts", "method:genre_guidance"]

      groups = Sources.all() |> Enum.map(& &1.group) |> Enum.uniq()

      assert groups == [
               "Ancient sources",
               "Editorial",
               "Theologians",
               "Biblical manuscripts",
               "Notes and reference",
               "Background",
               "Methods"
             ]

      assert %Sources.Source{label: "Josephus", tools: tools} = Sources.get("ancient:josephus")
      assert "search_ancient_sources" in tools
    end

    test "a source's tools are tools Bezalel has" do
      names = Enum.map(Tools.all(), & &1.name())
      for source <- Sources.all(), do: assert(source.tools -- names == [], source.key)
    end

    test "a tool is withheld only when every one of its sources is off" do
      withheld = &Tools.withheld(Preferences.new(excluded_sources: &1))

      assert Tools.withheld(%Preferences{}) == []
      assert withheld.([]) == []
      assert withheld.(["ane:context"]) == ["get_ane_context"]
      assert withheld.(["method:torah_weave"]) == ["get_torah_weave"]
      # A tool with content of its own besides a source keeps it.
      assert withheld.(["method:genre_guidance", "crossrefs:themes"]) == []

      notes = ~w(notes:study_notes notes:translation_notes_uw notes:translation_notes_sil)
      assert withheld.(Enum.take(notes, 2)) == []
      assert withheld.(notes) == ["get_study_notes"]

      ancient = for k <- Sources.keys(), String.starts_with?(k, "ancient:"), do: k
      assert withheld.(tl(ancient)) == []
      assert withheld.(ancient) == ["lookup_ancient_source", "search_ancient_sources"]

      theologians = for k <- Sources.keys(), String.starts_with?(k, "theology:"), do: k
      assert withheld.(theologians) == ["get_theology_context"]
    end
  end

  describe "Translations" do
    test "the NET (default) and the BSB, with the NET's required acknowledgement and link" do
      assert Translations.keys() == ["net", "bsb"]
      net = Translations.get("net")
      assert net.url == "http://netbible.org"

      assert net.copyright ==
               "Scripture quoted by permission. Quotations designated (NET) are from the NET " <>
                 "Bible® copyright ©1996, 2019 by Biblical Studies Press, L.L.C. " <>
                 "http://netbible.com All rights reserved."

      assert Translations.label(net) == "[NET](http://netbible.org)"
      assert Translations.label(Translations.get("bsb")) == "BSB"
      assert Translations.get("bsb").licence == "Public domain"
      assert Translations.get("kjv") == nil
    end
  end

  describe "Prompt" do
    @names Enum.map(Tools.all(), & &1.name())

    defp tools_named(text) do
      for [_, name] <- Regex.scan(~r/`([a-z]+(?:_[a-z]+)+)`/, text),
          name in @names,
          uniq: true,
          do: name
    end

    test "the fixed part: purpose, provenance rules and every tool" do
      fixed = Prompt.fixed(%Preferences{})
      assert fixed =~ "companion for studying the Bible"
      assert fixed =~ "Say where each claim comes from"
      assert fixed =~ "Don't invent"
      assert Enum.sort(tools_named(fixed)) == Enum.sort(@names)
    end

    test "the default approach is neutral: no sermon prep, no doctrinal frame, readings credited" do
      approach = Prompt.default_approach()
      prompt = Prompt.system_prompt(%Preferences{})

      assert prompt =~ approach
      assert approach =~ "Jewish"
      assert approach =~ "Catholic, Orthodox and Protestant"
      assert approach =~ "historical-critical"
      assert approach =~ "Credit each reading"

      for word <- ["sermon", "preach", "gospel", "Christ ", "faithful", "Scripture interprets"] do
        refute prompt =~ word, word
      end
    end

    test "the user's approach replaces the default; the fixed part stays" do
      prefs = Preferences.new(approach: "## My way\n\nAnswer as a Catholic catechist would.")
      prompt = Prompt.system_prompt(prefs)
      assert prompt =~ "Answer as a Catholic catechist would."
      refute prompt =~ Prompt.default_approach()
      assert String.starts_with?(prompt, Prompt.fixed(prefs))
    end

    test "switched-off sources are named; a withheld tool is left out of the guide" do
      default = Prompt.fixed(%Preferences{})

      assert default =~
               "## Sources switched off\n\n" <>
                 "Editorial verdicts; Genre guidance (Fee & Stuart)."

      prefs = Preferences.new(excluded_sources: ["ane:context", "theology:heiser"])
      fixed = Prompt.fixed(prefs)
      assert fixed =~ "Michael S. Heiser; Ancient Near East background."
      refute fixed =~ "Editorial verdicts"
      refute fixed =~ "`get_ane_context`"
      assert fixed =~ "`get_theology_context`"

      none = Prompt.fixed(Preferences.new(excluded_sources: []))
      refute none =~ "switched off"
    end

    test "the host's surface section comes last; core has no phone formatting" do
      prompt = Prompt.system_prompt(%Preferences{}, surface: "## Formatting\n\nNarrow column.")
      assert String.ends_with?(prompt, "## Formatting\n\nNarrow column.")
      refute Prompt.system_prompt(%Preferences{}) =~ "phone"
    end

    test "with ask_model offered, the rule for asking another model, before the surface section" do
      prompt = Prompt.system_prompt(%Preferences{}, ask_model: true, surface: "## Formatting")
      assert prompt =~ Prompt.other_models()
      assert String.ends_with?(prompt, "## Formatting")

      # Not offered, not mentioned: the model can't call a tool it hasn't got.
      refute Prompt.system_prompt(%Preferences{}) =~ "ask_model"
    end
  end
end

defmodule Bezalel.Study.PreferencesCurrentTest do
  # Sets :preferences in the app env, so not async.
  use ExUnit.Case, async: false

  alias Bezalel.Study.{Preferences, Tools.LookupVerse}

  def for_session(user_limits, ctx), do: Map.get(user_limits, ctx[:session_id], %{})

  setup do
    previous = Application.fetch_env(:bezalel_core, :preferences)

    on_exit(fn ->
      case previous do
        {:ok, value} -> Application.put_env(:bezalel_core, :preferences, value)
        :error -> Application.delete_env(:bezalel_core, :preferences)
      end
    end)
  end

  test "unset, the defaults" do
    Application.delete_env(:bezalel_core, :preferences)
    assert Preferences.current(%{session_id: "s"}) == %Preferences{}
  end

  test "the host's {m, f, a} gets the tool ctx, and its answer is normalised" do
    users = %{"s1" => %{limit: 3, translation: "bsb"}, "s2" => %{limit: 500}}
    Application.put_env(:bezalel_core, :preferences, {__MODULE__, :for_session, [users]})

    assert %Preferences{limit: 3, translation: "bsb"} = Preferences.current(%{session_id: "s1"})
    assert Preferences.current(%{session_id: "s2"}).limit == 8
    assert Preferences.current().limit == 8
  end

  test "a tool's run/2 follows the session's preferences" do
    users = %{"bsb" => %{translation: "bsb", excluded_sources: []}}
    Application.put_env(:bezalel_core, :preferences, {__MODULE__, :for_session, [users]})

    assert {:ok, {:details, text, result}} =
             LookupVerse.run(%{"reference" => "Exodus 31:3"}, %{session_id: "bsb"})

    assert result.translation.key == "bsb"
    assert text =~ "## Genre:"
    assert Enum.any?(result.citations, &(&1.url == "https://biblehub.com/exodus/31-3.htm"))
    assert Enum.any?(result.citations, &(&1.work == "fee_stuart"))

    assert {:ok, {:details, default, other}} =
             LookupVerse.run(%{"reference" => "Exodus 31:3"}, %{session_id: "other"})

    assert other.translation.key == "net"
    refute default =~ "## Genre:"
    assert Enum.any?(other.citations, &(&1.url == "https://netbible.org/bible/Exodus+31:3"))
    refute Enum.any?(other.citations, &(&1.work == "fee_stuart"))
  end
end
