defmodule Bezalel.Data.TextFabricTest do
  use ExUnit.Case, async: true

  alias Bezalel.Data.TextFabric

  defp file(lines),
    do: Enum.join(["@node", TextFabric.licence(), "@valueType=str", "" | lines], "\n") <> "\n"

  test "values follow the previous node unless a spec names the node, a range or a list" do
    bytes = file(["a", "5\tb", "c", "8-9\td", "11,13-14\te\\tf", ""])
    values = TextFabric.feature("x.tf", bytes, 1, 20)

    assert values == %{
             1 => "a",
             5 => "b",
             6 => "c",
             8 => "d",
             9 => "d",
             11 => "e\tf",
             13 => "e\tf",
             14 => "e\tf",
             15 => ""
           }

    assert TextFabric.feature("x.tf", bytes, 6, 9) == %{6 => "c", 8 => "d", 9 => "d"}
  end

  test "a file without the CC BY-NC declaration, a bad header or nodes out of order stops" do
    assert_raise ArgumentError, ~r/no CC BY-NC 4.0 declaration/, fn ->
      TextFabric.feature("x.tf", "@node\n@valueType=str\n\na\n", 1, 5)
    end

    assert_raise ArgumentError, ~r/malformed Text-Fabric header/, fn ->
      TextFabric.feature("x.tf", "@node\n#{TextFabric.licence()}\nnot a header\n\na\n", 1, 5)
    end

    assert_raise ArgumentError, ~r/node 3 does not follow node 5/, fn ->
      TextFabric.feature("x.tf", file(["5\ta", "3\tb"]), 1, 9)
    end
  end

  test "types and one slot range per node; split slots stop the build" do
    otype = file(["1-10\tsign", "11-12\tline", "13\tscroll"])

    assert TextFabric.types(otype) == %{
             "sign" => {1, 10},
             "line" => {11, 12},
             "scroll" => {13, 13}
           }

    assert_raise ArgumentError, ~r/no "line" nodes/, fn ->
      TextFabric.types(file(["1-3\tsign"]))
    end

    slots = file(["11\t1-4", "5-10", "1-10"])
    assert TextFabric.slots(slots, 11, 13) == %{11 => 1..4, 12 => 5..10, 13 => 1..10}

    assert_raise ArgumentError, ~r/node 11 has discontinuous slots/, fn ->
      TextFabric.slots(file(["11\t1-2,4"]), 11, 11)
    end
  end
end
