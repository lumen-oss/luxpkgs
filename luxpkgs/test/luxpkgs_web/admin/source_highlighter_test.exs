defmodule LuxpkgsWeb.Admin.SourceHighlighterTest do
  use ExUnit.Case, async: true

  alias LuxpkgsWeb.Admin.SourceHighlighter

  test "splits lines and marks Lua tokens" do
    lines = SourceHighlighter.lines(~s(local x = "hi" -- note\nreturn x))

    assert length(lines) == 2
    assert Enum.any?(hd(lines), &match?({:keyword, "local"}, &1))
    assert Enum.any?(hd(lines), &match?({:operator, "="}, &1))
    assert Enum.any?(hd(lines), &match?({:string, ~s("hi")}, &1))
    assert Enum.any?(hd(lines), &match?({:comment, "-- note"}, &1))
    assert Enum.any?(List.last(lines), &match?({:keyword, "return"}, &1))
  end

  test "keeps multi-line Lua strings in one token type" do
    lines = SourceHighlighter.lines("x = [[hello\nworld]]")

    assert Enum.any?(hd(lines), &match?({:string, "[[hello"}, &1))
    assert Enum.any?(List.last(lines), &match?({:string, "world]]"}, &1))
  end

  test "does not treat TOML table headers as long strings" do
    lines = SourceHighlighter.lines("[[package]]\nname = \"luxpkgs\"", :lux_toml)

    refute Enum.any?(hd(lines), &match?({:string, _}, &1))
    assert Enum.any?(List.last(lines), &match?({:string, ~s("luxpkgs")}, &1))
  end

  test "preserves empty and trailing lines" do
    assert length(SourceHighlighter.lines("a\n\nb")) == 3
    assert length(SourceHighlighter.lines("a\n")) == 2
  end
end
