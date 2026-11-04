defmodule LuxpkgsWeb.Admin.SourceHighlighter do
  @moduledoc """
  Splits source text into lines of lightweight syntax tokens.

  This is not a full parser. It recognizes the common Lua and TOML tokens
  used in rockspecs so the admin viewer can highlight them without a
  JavaScript highlighter or a new dependency pulling a bunch of languages
  we do not care about over here.
  """

  @keywords ~w(and break do else elseif end false for function goto if in local nil not or repeat return then true until while)

  @lua_tokens [
    comment: ~S{\A--\[(=*)\[.*?\]\1\]},
    comment: ~S{\A--[^\n]*},
    string: ~S{\A\[(=*)\[.*?\]\1\]},
    string: ~S{\A"(?:\\.|[^"\\])*"},
    string: ~S{\A'(?:\\.|[^'\\])*'},
    number: ~S{\A\d+(?:\.\d+)*(?:[eE][+-]?\d+)?},
    word: ~S{\A[A-Za-z_][A-Za-z0-9_-]*},
    operator: ~S{\A[=+\-*\/%^<>~#]+},
    space: ~S{\A\s+},
    plain: ~S|\A[^\w\s]+|
  ]

  @toml_tokens [
    comment: ~S{\A#[^\n]*},
    string: ~S{\A"""(?:.|\n)*?"""},
    string: ~S{\A'''(?:.|\n)*?'''},
    string: ~S{\A"(?:\\.|[^"\\])*"},
    string: ~S{\A'(?:\\.|[^'\\])*'},
    number: ~S{\A\d+(?:\.\d+)*(?:[eE][+-]?\d+)?},
    word: ~S{\A[A-Za-z_][A-Za-z0-9_-]*},
    operator: ~S{\A[=+\-*\/%^<>~#]+},
    space: ~S{\A\s+},
    plain: ~S|\A[^\w\s]+|
  ]

  @doc """
  Returns a list of lines, each containing `{type, text}` tokens.

  Types are `:keyword`, `:string`, `:number`, `:comment`, `:operator`
  and `:plain`.
  """
  def lines(content, kind \\ :rockspec) when is_binary(content) do
    tokens = if kind == :lux_toml, do: compile(@toml_tokens), else: compile(@lua_tokens)

    content
    |> tokenize(tokens, [])
    |> Enum.reduce([[]], &append_token/2)
    |> Enum.reverse()
    |> Enum.map(fn line ->
      line
      |> Enum.reverse()
      |> Enum.reject(fn {_type, text} -> text == "" end)
    end)
  end

  defp compile(tokens) do
    Enum.map(tokens, fn {type, pattern} -> {type, Regex.compile!(pattern, "s")} end)
  end

  defp tokenize("", _tokens, acc), do: Enum.reverse(acc)

  defp tokenize(text, tokens, acc) do
    {type, value, rest} = next_token(text, tokens)
    tokenize(rest, tokens, [{type, value} | acc])
  end

  defp next_token(text, tokens) do
    Enum.find_value(tokens, fn {type, regex} ->
      case Regex.run(regex, text) do
        [value | _] ->
          rest = binary_part(text, byte_size(value), byte_size(text) - byte_size(value))
          {classify(type, value), value, rest}

        nil ->
          nil
      end
    end) || {:plain, binary_part(text, 0, 1), binary_part(text, 1, byte_size(text) - 1)}
  end

  defp classify(:word, value) when value in @keywords, do: :keyword
  defp classify(type, _value), do: type

  defp append_token({type, text}, lines) do
    text
    |> String.split("\n", trim: false)
    |> Enum.with_index()
    |> Enum.reduce(lines, fn
      {part, 0}, [current | rest] ->
        [[{type, part} | current] | rest]

      {part, _index}, [current | rest] ->
        [[{type, part}], current | rest]
    end)
  end
end
