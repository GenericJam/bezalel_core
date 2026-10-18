defmodule Bezalel.Agent.ReplyTest do
  # The blocks a reply folds into: a plain one-line header, and Markdown
  # (the model's or a tool's) under it, which the chat renders natively.
  use ExUnit.Case, async: true

  alias Bezalel.Agent.Reply

  defp summary(text) do
    Reply.new(1, "m")
    |> Reply.apply(%{type: :message_update, kind: :text, delta: text})
    |> Reply.blocks()
    |> List.last()
  end

  describe "a SUMMARY's header and rest" do
    test "a heading first is the header, without its marks; the Markdown after it is the rest" do
      text = "## Exodus 31:3\n\nBezalel is **filled** with the *Spirit*.\n\n- called\n- filled"
      b = summary(text)

      assert {b["first"], b["rest"], b["text"]} ==
               {"Exodus 31:3", "Bezalel is **filled** with the *Spirit*.\n\n- called\n- filled",
                text}

      refute Map.has_key?(b, "cut")
    end

    test "a first sentence loses its emphasis, code and link marks; the rest keeps them" do
      b = summary("See **[Exodus](https://x.org/ex)** and `ruach`. Then **more**.")
      assert {b["first"], b["rest"]} == {"See Exodus and ruach.", "Then **more**."}
    end

    test "a list item or a quote first is the header line" do
      assert %{"first" => "called by name", "rest" => "- filled"} =
               summary("- called by name\n- filled")

      assert %{"first" => "called", "rest" => "2. filled"} = summary("1. called\n2. filled")
      assert %{"first" => "A word.", "rest" => "Mine."} = summary("> A word.\n\nMine.")
    end

    test "a table or a code block first stays whole under its first line" do
      table = "| Ref | Hebrew |\n|--|--|\n| Ex 31:3 | ruach |"
      assert %{"first" => "Ref · Hebrew", "rest" => ^table, "cut" => true} = summary(table)

      code = "```elixir\nIO.puts(:hi)\n```"
      assert %{"first" => "IO.puts(:hi)", "rest" => ^code, "cut" => true} = summary(code)
    end

    test "a header that would leave the rest's Markdown unbalanced keeps the text whole" do
      text = "*Called. Filled.* That is Bezalel."

      assert %{"first" => "Called. Filled. That is Bezalel.", "rest" => ^text, "cut" => true} =
               summary(text)

      link = "Read [Gen. 1](https://x.org) first."
      assert %{"rest" => ^link, "cut" => true} = summary(link)

      for text <- ["_Called. Filled._ That is Bezalel.", "__Called. Filled.__ That is Bezalel."] do
        assert %{"first" => "Called. Filled. That is Bezalel.", "rest" => ^text, "cut" => true} =
                 summary(text)
      end

      # An underscore inside a word is no emphasis.
      assert %{"first" => "Call lookup_verse.", "rest" => "Then read."} =
               summary("Call lookup_verse. Then read.")
    end

    test "a long first line is cut at a word; the rest is the whole text" do
      text = "Bezalel is **filled** with the Spirit of God. He is the first."
      assert %{"first" => "Bezalel is filled with the…", "rest" => ^text} = summary(text)
    end

    test "while streaming, the rest is the Markdown so far, unclosed marks included" do
      r = Reply.new(1, "m")

      r =
        Reply.apply(r, %{type: :message_update, kind: :text, delta: "## Bezalel\n\nHe is **fil"})

      assert %{"first" => "Bezalel", "rest" => "He is **fil"} = List.last(Reply.blocks(r))

      r = Reply.apply(r, %{type: :message_update, kind: :text, delta: "led**."})
      assert %{"first" => "Bezalel", "rest" => "He is **filled**."} = List.last(Reply.blocks(r))
    end
  end

  test "THINKING keeps the model's Markdown too" do
    r =
      Reply.apply(Reply.new(1, "m"), %{
        type: :message_update,
        kind: :thinking,
        delta: "Plan **first**. Look up `Ex 31:3`.\n\n1. verse\n2. word"
      })

    assert [%{"type" => "THINKING", "first" => "Plan first.", "rest" => rest}] = Reply.blocks(r)
    assert rest == "Look up `Ex 31:3`.\n\n1. verse\n2. word"
  end

  describe "a TOOL CALL's result" do
    defp tool(text, error \\ false) do
      Reply.new(1, "m")
      |> Reply.apply(%{type: :tool_execution_start, id: "t", name: "lookup", arguments: %{}})
      |> Reply.apply(%{
        type: :tool_execution_end,
        id: "t",
        name: "lookup",
        text: text,
        is_error: error,
        card: nil
      })
      |> Reply.blocks()
      |> hd()
    end

    test "is the tool's Markdown as it is" do
      text = "## Exo.31.3\n\n| v | text |\n|--|--|\n| 3 | filled |"
      assert tool(text)["rest"] == text
    end

    test "shows its first six lines with words, whole, and a paragraph of its own says there's more" do
      rows = for n <- 1..10, do: "| #{n} | row #{n} |"
      text = Enum.join(["## Rows", "", "| n | row |", "|--|--|" | rows], "\n")

      assert tool(text)["rest"] ==
               "## Rows\n\n| n | row |\n|--|--|\n| 1 | row 1 |\n| 2 | row 2 |\n| 3 | row 3 |\n\n…"
    end

    test "an error says so before its text" do
      assert tool("The core study pack isn't installed.", true)["rest"] ==
               "Error: The core study pack isn't installed."
    end

    test "a first line longer than the limit on its own is cut at a word, and says there's more" do
      text = String.duplicate("word ", 200)
      rest = tool(text)["rest"]

      assert String.ends_with?(rest, "word\n\n…")
      assert String.length(rest) <= 503
    end
  end

  test "header/1 reads one Markdown line as plain text" do
    for {line, plain} <- [
          {"### **Bold** heading", "Bold heading"},
          {"> - [ ] a task", "a task"},
          {"![a picture](https://x.org/p.png) and ~~gone~~", "a picture and gone"},
          {"| a | b |", "a · b"},
          {"```", ""}
        ],
        do: assert(Reply.header(line) == plain, line)
  end
end
