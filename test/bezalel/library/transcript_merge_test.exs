defmodule Bezalel.Library.TranscriptMergeTest do
  use ExUnit.Case, async: true

  alias Bezalel.Library.Transcript
  alias Rho.Session

  @moduletag :tmp_dir

  @model "anthropic:claude-haiku-4-5"

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

  defp open(path) do
    {:ok, s, branch} = Session.open(path, @model)
    {s, branch}
  end

  defp lines(path),
    do: path |> File.read!() |> String.split("\n", trim: true) |> Enum.map(&Jason.decode!/1)

  defp questions(branch),
    do: for(%{role: :user, text: t} <- Transcript.messages(branch, "s"), do: t)

  # A conversation both had (`base` turns), then `ours` turns on the phone
  # and `theirs` on the website, `first` saying which side went on first.
  defp diverge(dir, base, ours, theirs, first) do
    s = Enum.reduce(base, Session.new(Path.join(dir, "phone"), @model, dir), &turn(&2, &1))
    server = Path.join(dir, "server.jsonl")
    File.cp!(s.path, server)
    base_ids = for %{"id" => id} <- lines(s.path), do: id

    go = fn
      :phone -> Enum.reduce(ours, elem(open(s.path), 0), &turn(&2, &1))
      :server -> Enum.reduce(theirs, elem(open(server), 0), &turn(&2, &1))
    end

    Enum.each(if(first == :phone, do: [:phone, :server], else: [:server, :phone]), go)
    {s.path, server, base_ids}
  end

  defp apply_move(path, {parent, copies}) do
    {s, _} = open(path)
    Enum.reduce(copies, %{s | leaf_id: parent}, &elem(Session.append(&2, &1), 0))
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
      {phone, server, base_ids} = diverge(dir, ["q"], ours, theirs, first)

      assert {:ok, move, count} =
               Transcript.merge(base_ids, elem(open(phone), 1), elem(open(server), 1))

      assert count == 2 * length(theirs)
      apply_move(phone, move)
      {_s, branch} = open(phone)

      expected = if first == :phone, do: ["q"] ++ ours ++ theirs, else: ["q"] ++ theirs ++ ours
      assert questions(branch) == expected, "case #{i}"

      # one linear branch, ids unique in the whole file (originals kept)
      assert Enum.map(tl(branch), & &1["parentId"]) == Enum.map(Enum.drop(branch, -1), & &1["id"])
      ids = for %{"id" => id} <- lines(phone), do: id
      assert ids == Enum.uniq(ids)

      notice = List.last(branch)
      assert Session.notice_kind(notice) == :notice

      assert notice["content"] ==
               "#{count} messages from your computer were added while your phone was offline."
    end
  end

  test "nothing new from the website, or only what the phone has: nothing to merge",
       %{tmp_dir: dir} do
    {phone, server, base_ids} = diverge(dir, ["q"], ["p1"], [], :phone)
    assert Transcript.merge(base_ids, elem(open(phone), 1), elem(open(server), 1)) == :none

    # the website's copy already holds the phone's turn (an earlier pull)
    {_s, branch} = open(phone)
    assert Transcript.merge(base_ids, branch, branch) == :none
  end

  test "the phone's own turns after a merge stay on the file as an inactive branch",
       %{tmp_dir: dir} do
    {phone, server, base_ids} = diverge(dir, ["q"], ["p1"], ["s1"], :server)
    {_s, before} = open(phone)
    own = for e <- before, e["id"] not in base_ids, do: e["id"]

    {:ok, move, 2} = Transcript.merge(base_ids, before, elem(open(server), 1))
    apply_move(phone, move)
    {_s, branch} = open(phone)

    file_ids = for %{"id" => id} <- lines(phone), do: id
    assert Enum.all?(own, &(&1 in file_ids))
    refute Enum.any?(own, &(&1 in Enum.map(branch, fn e -> e["id"] end)))
  end
end
