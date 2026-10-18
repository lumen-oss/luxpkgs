defmodule LuxpkgsRockspecVerifier.Rockspec do
  def verify(rockspec, %{
        expected_name: expected_name,
        expected_version: expected_version
      }) do
    sandboxed_state = :luerl_sandbox.init()

    Regex.match?(~r/^[a-zA-Z0-9_\.\-]+$/, expected_name) and
      case :luerl_sandbox.run(
             rockspec,
             %{
               max_reductions: 500
               # max_time: ...
             },
             sandboxed_state
           ) do
        {:ok, _, state} ->
          with {:ok, %Version{}} <- Version.parse(expected_version),
               {:ok, "3.0", _} <- Luerl.get_table_keys_dec(state, ["rockspec_format"]),
               {:ok, ^expected_name, _} <-
                 Luerl.get_table_keys_dec(state, ["package"]),
               {:ok, ^expected_version, _} <-
                 Luerl.get_table_keys_dec(state, ["version"]),
               {:ok, source, _} <- Luerl.get_table_keys_dec(state, ["source"]),
               {:ok, build, _} <- Luerl.get_table_keys_dec(state, ["build"]) do
            {has_tag_or_hash, has_git_url} =
              Enum.reduce(source, {false, false}, fn
                {tag_or_hash, _}, {_, has_url} when tag_or_hash in ["tag", "hash"] ->
                  {true, has_url}

                {"url", "git+" <> _}, {has_tag, _} ->
                  {has_tag, true}

                {"url", "git://" <> _}, {has_tag, _} ->
                  {has_tag, true}

                _, acc ->
                  acc
              end)

            has_url =
              has_git_url or
                Enum.any?(source, fn
                  {"url", _} -> true
                  _ -> false
                end)

            ((has_tag_or_hash and has_git_url) or has_url) and
              Enum.any?(build, fn
                {"type", _} -> true
                _ -> false
              end)
          else
            _ -> false
          end

        {:error, _, _} ->
          false

        {:error, _} ->
          false
      end
  end

  @doc """
  Less secure endpoint for extracting data out of a package (luarocks legacy support).
  """
  def parse(rockspec_text) do
    sandboxed_state = :luerl_sandbox.init()

    case :luerl_sandbox.run(rockspec_text, %{max_reductions: 500}, sandboxed_state) do
      {:ok, _, state} ->
        package = get_field(state, "package")
        version = get_field(state, "version")
        summary = get_field(state, "summary")
        description = get_field(state, "description")

        case {package, version} do
          {nil, _} ->
            {:error}

          {_, nil} ->
            {:error}

          {pkg, ver} ->
            {:ok,
             %{
               package: pkg,
               version: ver,
               summary: summary,
               description: description
             }}
        end

      {:error, _} ->
        {:error}
    end
  end

  defp get_field(state, field) do
    case Luerl.get_table_keys_dec(state, [field]) do
      {:ok, value, _} when is_binary(value) -> value
      _ -> nil
    end
  end
end
