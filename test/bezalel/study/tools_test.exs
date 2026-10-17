defmodule Bezalel.Study.ToolsTest do
  # What the model is told must match what it has: every tool the
  # descriptions or the system prompt name is one Bezalel offers.
  use ExUnit.Case, async: true

  alias Bezalel.Study.{Prompt, Tools}

  @names Enum.map(Tools.all(), & &1.name())

  # `snake_case` names in backticks that look like tool names.
  defp tools_named(text) do
    for [_, name] <- Regex.scan(~r/`([a-z]+(?:_[a-z]+)+)`/, text),
        String.match?(
          name,
          ~r/^(lookup|word|search|get|parse|people|find|explore|graph|compare|list)_/
        ),
        uniq: true,
        do: name
  end

  test "every tool is a rho tool the model can be offered, under a unique name" do
    for tool <- Tools.all() do
      assert Rho.Tool.tool?(tool)
      assert %ReqLLM.Tool{} = Rho.Tool.to_req_llm(tool)
    end

    assert Enum.count(Enum.uniq(@names)) == 25
  end

  test "tool descriptions point only at tools Bezalel has" do
    for tool <- Tools.all() do
      assert tools_named(tool.description()) -- @names == [], tool.name()
    end
  end

  test "the system prompt covers every tool and names no other" do
    named = tools_named(Prompt.system_prompt())
    assert named -- @names == []
    assert @names -- named == []
  end

  test "every hint lookup_verse gives names a tool Bezalel has" do
    {:ok, {:details, text, _result}} =
      Tools.LookupVerse.run(%{"reference" => "Exodus 31:2-3"}, %{})

    assert tools_named(text) -- @names == []
  end

  test "a number too big for SQLite is refused as an argument, not a crash" do
    huge = 99_999_999_999_999_999_999_999

    for {tool, args} <- [
          {Tools.GetCrossReferences, %{"reference" => "Exodus 31:3", "limit" => huge}},
          {Tools.GetCrossReferences, %{"reference" => "Exodus 31:3", "min_strength" => huge}},
          {Tools.SearchLexicon, %{"query" => "wisdom", "limit" => Integer.to_string(huge)}},
          {Tools.SearchByStrongs, %{"strongs" => "H2451", "limit" => huge}},
          {Tools.FindSimilarPassages, %{"reference" => "Psalm 22:18", "limit" => huge}}
        ] do
      assert {status, text} = tool.run(args, %{}), inspect({tool, args})
      assert status in [:ok, :error] and is_binary(text)
    end
  end
end
