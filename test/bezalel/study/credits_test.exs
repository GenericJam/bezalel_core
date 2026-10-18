defmodule Bezalel.Study.CreditsTest do
  use ExUnit.Case, async: true

  alias Bezalel.Study.{Credits, Translations}

  test "every source names at least one licence" do
    for {title, _text, licences, _links} <- Credits.sources() do
      assert licences != [], "#{title} has no licence"
    end
  end

  test "the NET is credited with its acknowledgement verbatim" do
    net = Translations.get("net")
    assert {_, text, _, [url]} = Enum.find(Credits.sources(), &(elem(&1, 0) == net.name))
    assert text == net.copyright
    assert url == net.url
  end
end
