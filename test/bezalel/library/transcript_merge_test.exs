defmodule Bezalel.Library.TranscriptMergeTest do
  use ExUnit.Case, async: true

  alias Bezalel.Library.Transcript
  alias Rho.Session

  @moduletag :tmp_dir

  @model "anthropic:claude-haiku-4-5"
  @other "openai:gpt-5"

  defp turn(s, question) do
    {s, _} = Session.append(s, Transcript.user(question))

    {s, _} =
      Session.append(
        s,
        Transcript.reply(%{blocks: [%{"id" => "sum", "first" => "re " <> question}]})
      )

    # entries a millisecond apart, so which side began first is unambiguous
    Process.sleep(2)
    s
  end

  defp turns(path, questions), do: Enum.reduce(questions, elem(open(path), 0), &turn(&2, &1))

  defp open(path) do
    {:ok, s, branch} = Session.open(path, @model)
    {s, branch}
  end

  defp branch(path), do: elem(open(path), 1)
  defp model(path), do: elem(open(path), 0).model
  defp append(path, entry), do: path |> open() |> elem(0) |> Session.append(entry)

  defp lines(path),
    do: path |> File.read!() |> String.split("\n", trim: true) |> Enum.map(&Jason.decode!/1)

  defp questions(branch),
    do: for(%{role: :user, text: t} <- Transcript.messages(branch, "s"), do: t)

  # What the chat shows, in order: each question, each reply's summary.
  defp shown(branch) do
    for m <- Transcript.messages(branch, "s"),
        do: if(m.role == :user, do: m.text, else: hd(m.blocks)["first"])
  end

  # A conversation both had (`base` turns, then `more` on the file): the
  # phone's file, the website's copy of it, and the entries they share.
  defp shared(dir, base, more \\ fn _path -> :ok end) do
    s = Enum.reduce(base, Session.new(Path.join(dir, "phone"), @model, dir), &turn(&2, &1))
    more.(s.path)
    server = Path.join(dir, "server.jsonl")
    File.cp!(s.path, server)
    {s.path, server, lines(s.path)}
  end

  # Then `ours` turns on the phone and `theirs` on the website, `first`
  # saying which side went on first.
  defp diverge(dir, base, ours, theirs, first) do
    {phone, server, base} = shared(dir, base)

    go = fn
      :phone -> turns(phone, ours)
      :server -> turns(server, theirs)
    end

    Enum.each(if(first == :phone, do: [:phone, :server], else: [:server, :phone]), go)
    {phone, server, base}
  end

  # As the apps apply a move: a move with nothing to copy puts a marker.
  defp apply_move(path, {parent, []}), do: apply_move(path, {parent, [Transcript.marker()]})

  defp apply_move(path, {parent, copies}) do
    {s, _} = open(path)
    Enum.reduce(copies, %{s | leaf_id: parent}, &elem(Session.append(&2, &1), 0))
  end

  # Delete on `path`: the entries of the messages asked as `questions`
  # (and their replies when `replies?`). Returns the leaf before and after.
  defp delete(path, questions, replies?) do
    branch = branch(path)

    ids =
      for m <- Transcript.messages(branch, "s"),
          (m.role == :user and m.text in questions) or
            (replies? and m.role == :agent and
               Enum.any?(questions, &(hd(m.blocks)["first"] == "re " <> &1))),
          id <- m.entries,
          do: id

    before = List.last(branch)["id"]
    apply_move(path, Transcript.delete(branch, ids))
    {before, List.last(branch(path))["id"]}
  end

  defp merged(phone, server, base) do
    assert {:ok, move, count} = Transcript.merge(base, branch(phone), branch(server))
    apply_move(phone, move)
    {branch(phone), count}
  end

  # One linear branch, ids unique in the whole file (originals kept), the
  # notice last and saying `count`.
  defp assert_sound(phone, branch, count) do
    assert Enum.map(tl(branch), & &1["parentId"]) == Enum.map(Enum.drop(branch, -1), & &1["id"])
    ids = for %{"id" => id} <- lines(phone), do: id
    assert ids == Enum.uniq(ids)

    notice = List.last(branch)
    assert Session.notice_kind(notice) == :notice

    assert notice["content"] ==
             "#{count} messages from your computer were added while your phone was offline."
  end

  test "both sides' turns end up on the phone's active branch, in the order they began",
       %{tmp_dir: dir} do
    cases = [
      {[], ["s1"], :phone},
      {["p1"], ["s1"], :phone},
      {["p1"], ["s1"], :server},
      {["p1", "p2"], ["s1"], :server},
      {["p1"], ["s1", "s2", "s3"], :phone},
      {[], ["s1", "s2"], :server}
    ]

    for {{ours, theirs, first}, i} <- Enum.with_index(cases) do
      dir = Path.join(dir, "#{i}")
      {phone, server, base} = diverge(dir, ["q"], ours, theirs, first)
      {branch, count} = merged(phone, server, base)

      assert count == 2 * length(theirs)
      expected = if first == :phone, do: ["q"] ++ ours ++ theirs, else: ["q"] ++ theirs ++ ours
      assert questions(branch) == expected, "case #{i}"
      assert_sound(phone, branch, count)
    end
  end

  test "a Delete on the website wins; its copies of the shared messages aren't new ones",
       %{tmp_dir: dir} do
    for first <- [:phone, :server] do
      dir = Path.join(dir, "#{first}")
      {phone, server, base} = shared(dir, ["q1", "q2", "q3"])

      server_side = fn ->
        delete(server, ["q1"], false)
        turns(server, ["s1"])
      end

      if first == :phone, do: turns(phone, ["p1"])
      server_side.()
      if first == :server, do: turns(phone, ["p1"])

      {branch, count} = merged(phone, server, base)
      assert count == 2

      new =
        if first == :phone,
          do: ["p1", "re p1", "s1", "re s1"],
          else: ["s1", "re s1", "p1", "re p1"]

      assert shown(branch) == ["re q1", "q2", "re q2", "q3", "re q3"] ++ new
      assert_sound(phone, branch, count)
    end
  end

  test "an Undo on the website: its turn's copies are new, in the order it was asked",
       %{tmp_dir: dir} do
    {phone, server, base} = shared(dir, ["q1", "q2", "q3"])

    # the website deletes q2, asks s1, the phone asks p1, then the website undoes
    {before, after_delete} = delete(server, ["q2"], true)
    turns(server, ["s1"])
    turns(phone, ["p1"])
    apply_move(server, Transcript.undo(branch(server), before, after_delete))
    assert questions(branch(server)) == ["q1", "q2", "q3", "s1"]

    {branch, count} = merged(phone, server, base)
    assert count == 2
    assert questions(branch) == ["q1", "q2", "q3", "s1", "p1"]
    assert_sound(phone, branch, count)
  end

  test "a Delete on the phone stays when the website only added turns", %{tmp_dir: dir} do
    {phone, server, base} = shared(dir, ["q1", "q2", "q3"])
    turns(server, ["s1"])
    delete(phone, ["q1"], true)
    turns(phone, ["p1"])

    {branch, 2} = merged(phone, server, base)
    assert questions(branch) == ["q2", "q3", "s1", "p1"]
    assert_sound(phone, branch, 2)
  end

  test "a Delete on the website and nothing new from it still takes the message away",
       %{tmp_dir: dir} do
    {phone, server, base} = shared(dir, ["q1", "q2"])
    delete(server, ["q2"], true)
    turns(phone, ["p1"])

    assert {:ok, {_parent, copies} = move, 0} =
             Transcript.merge(base, branch(phone), branch(server))

    refute Enum.any?(copies, &Session.notice_kind/1)
    apply_move(phone, move)
    assert shown(branch(phone)) == ["q1", "re q1", "p1", "re p1"]
  end

  test "a model switch on the website survives the merge, also back to an earlier model",
       %{tmp_dir: dir} do
    # base: q1 on @model, a switch to @other, q2
    on_other = fn path ->
      append(path, Session.model_change(@other))
      turns(path, ["q2"])
    end

    for {website, i} <- Enum.with_index([[@model, "s1"], ["s0", @model, "s1"]]),
        first <- [:phone, :server] do
      dir = Path.join(dir, "#{i}-#{first}")
      {phone, server, base} = shared(dir, ["q1"], on_other)

      on_server = fn ->
        for step <- website,
            do:
              if(step == @model,
                do: append(server, Session.model_change(@model)),
                else: turns(server, [step])
              )
      end

      if first == :server, do: on_server.()
      turns(phone, ["p1"])
      if first == :phone, do: on_server.()
      assert model(server) == @model

      {branch, count} = merged(phone, server, base)
      asked = Enum.reject(website, &(&1 == @model))
      assert count == 2 * length(asked)
      new = if first == :phone, do: ["p1" | asked], else: asked ++ ["p1"]
      assert questions(branch) == ["q1", "q2" | new], "case #{i}, #{first}"
      assert model(phone) == @model, "case #{i}, #{first}"
      assert Enum.count(branch, &(&1["type"] == "model_change")) == 3
      assert_sound(phone, branch, count)
    end
  end

  test "a notice the website repeats (one the phone or the base also has) stays", %{tmp_dir: dir} do
    stopped = Session.custom(:notice, "Stopped.")
    {phone, server, base} = shared(dir, ["q1"], &append(&1, stopped))

    turns(phone, ["p1"])
    append(phone, stopped)
    turns(server, ["s1"])
    append(server, stopped)

    {branch, 2} = merged(phone, server, base)
    assert questions(branch) == ["q1", "p1", "s1"]
    assert Enum.count(branch, &(&1["content"] == "Stopped.")) == 3
    assert_sound(phone, branch, 2)
  end

  test "nothing new from the website, or only what the phone has: nothing to merge",
       %{tmp_dir: dir} do
    {phone, server, base} = diverge(dir, ["q"], ["p1"], [], :phone)
    assert Transcript.merge(base, branch(phone), branch(server)) == :none

    # the website's copy already holds the phone's turn (an earlier pull)
    assert Transcript.merge(base, branch(phone), branch(phone)) == :none
  end

  test "the phone's own turns after a merge stay on the file as an inactive branch",
       %{tmp_dir: dir} do
    {phone, server, base} = diverge(dir, ["q"], ["p1"], ["s1"], :server)
    base_ids = for %{"id" => id} <- base, do: id
    own = for e <- branch(phone), e["id"] not in base_ids, do: e["id"]

    {branch, 2} = merged(phone, server, base)

    file_ids = for %{"id" => id} <- lines(phone), do: id
    assert Enum.all?(own, &(&1 in file_ids))
    refute Enum.any?(own, &(&1 in Enum.map(branch, fn e -> e["id"] end)))
  end
end
