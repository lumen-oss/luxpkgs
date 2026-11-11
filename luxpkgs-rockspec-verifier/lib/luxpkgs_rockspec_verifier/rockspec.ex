defmodule LuxpkgsRockspecVerifier.Rockspec do
  # Kong's 48 KB rockspec measures ~525k reductions; the old 500-reduction
  # budget killed it. 750k leaves margin without a generous cap.
  @execution_limits %{max_reductions: 750_000, max_time: 1_000}

  def verify(rockspec, attrs) do
    match?({:ok, _}, verify_with_metadata(rockspec, attrs))
  end

  def verify_with_metadata(rockspec, %{
        expected_name: expected_name,
        expected_version: expected_version
      }) do
    if Regex.match?(~r/^[a-zA-Z0-9_\.\-]+$/, expected_name) do
      with {:ok, state} <- run(rockspec),
           :ok <- validate_format(state),
           :ok <- validate_identity(state, expected_name, expected_version),
           source when is_list(source) <- get_list(state, "source"),
           build when is_list(build) <- get_list(state, "build"),
           true <- valid_source?(source),
           true <- valid_build?(build) do
        {:ok, extract_metadata(state, build)}
      else
        _ -> :error
      end
    else
      :error
    end
  end

  @doc """
  Less secure endpoint for extracting data out of a package (luarocks legacy support).
  """
  def parse(rockspec_text) do
    with {:ok, state} <- run(rockspec_text),
         package when is_binary(package) <- get_string(state, "package"),
         version when is_binary(version) <- get_string(state, "version") do
      metadata = extract_metadata(state, get_list(state, "build") || [])

      {:ok,
       %{
         package: package,
         version: version,
         summary: metadata["summary"],
         description: metadata["detailed"],
         metadata: metadata
       }}
    else
      _ -> {:error}
    end
  end

  defp run(rockspec) do
    case :luerl_sandbox.run(rockspec, @execution_limits, :luerl_sandbox.init()) do
      {:ok, _, state} -> {:ok, state}
      _ -> :error
    end
  end

  defp validate_format(state) do
    case Luerl.get_table_keys_dec(state, ["rockspec_format"]) do
      {:ok, "3.0", _} -> :ok
      _ -> :error
    end
  end

  defp validate_identity(state, expected_name, expected_version) do
    with {:ok, %Version{}} <- Version.parse(expected_version),
         {:ok, ^expected_name, _} <- Luerl.get_table_keys_dec(state, ["package"]),
         {:ok, ^expected_version, _} <- Luerl.get_table_keys_dec(state, ["version"]) do
      :ok
    else
      _ -> :error
    end
  end

  defp valid_source?(source) do
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

    (has_tag_or_hash and has_git_url) or has_url
  end

  defp valid_build?(build) do
    Enum.any?(build, fn
      {"type", _} -> true
      _ -> false
    end)
  end

  defp extract_metadata(state, build) do
    description = get_value(state, "description")

    {summary, detailed, license, homepage, issues_url, labels} =
      case description do
        description when is_list(description) ->
          {
            description |> table_get("summary") |> string_or_nil(),
            description |> table_get("detailed") |> string_or_nil(),
            description |> table_get("license") |> string_or_nil(),
            description |> table_get("homepage") |> string_or_nil(),
            description |> table_get("issues_url") |> string_or_nil(),
            description |> table_get("labels") |> string_list()
          }

        description when is_binary(description) ->
          {nil, string_or_nil(description), nil, nil, nil, []}

        _ ->
          {nil, nil, nil, nil, nil, []}
      end

    %{}
    |> put_if("summary", summary || get_string(state, "summary"))
    |> put_if("detailed", detailed || get_string(state, "description"))
    |> put_if("license", license)
    |> put_if("homepage", homepage)
    |> put_if("issues_url", issues_url)
    |> put_if("labels", labels)
    |> put_if("lua", get_string(state, "lua"))
    |> put_if("platforms", get_list(state, "supported_platforms") |> string_list())
    |> put_if("dependencies", get_list(state, "dependencies") |> string_list())
    |> put_if(
      "external_dependencies",
      get_list(state, "external_dependencies") |> external_dependencies()
    )
    |> put_if("build_type", build |> table_get("type") |> string_or_nil())
  end

  defp get_value(state, field) do
    case Luerl.get_table_keys_dec(state, [field]) do
      {:ok, value, _} -> value
      _ -> nil
    end
  end

  defp get_string(state, field) do
    state |> get_value(field) |> string_or_nil()
  end

  defp get_list(state, field) do
    case get_value(state, field) do
      value when is_list(value) -> value
      _ -> nil
    end
  end

  defp table_get(table, key) when is_list(table) do
    case List.keyfind(table, key, 0) do
      {^key, value} -> value
      _ -> nil
    end
  end

  defp table_get(_table, _key), do: nil

  defp table_values(table) when is_list(table) do
    Enum.flat_map(table, fn
      {_key, value} -> [value]
      value -> [value]
    end)
  end

  defp table_values(_table), do: []

  defp string_list(value) when is_binary(value) do
    [string_or_nil(value)] |> Enum.reject(&is_nil/1)
  end

  defp string_list(value) when is_list(value) do
    value
    |> table_values()
    |> Enum.flat_map(fn
      value when is_binary(value) -> [string_or_nil(value)]
      _ -> []
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp string_list(_value), do: []

  defp external_dependencies(value) when is_list(value) do
    Enum.flat_map(value, fn
      {name, props} when is_binary(name) ->
        case string_or_nil(name) do
          nil -> []
          name -> external_dependency(name, props)
        end

      _ ->
        []
    end)
  end

  defp external_dependencies(_value), do: []

  defp external_dependency(name, props) when is_list(props) do
    [
      %{"name" => name}
      |> put_if("header", props |> table_get("header") |> string_or_nil())
      |> put_if("library", props |> table_get("library") |> string_or_nil())
    ]
  end

  defp external_dependency(name, library) when is_binary(library) do
    case string_or_nil(library) do
      nil -> []
      library -> [%{"name" => name, "library" => library}]
    end
  end

  defp external_dependency(_name, _props), do: []

  defp string_or_nil(value) when is_binary(value) do
    if String.valid?(value) do
      case String.trim(value) do
        "" -> nil
        value -> value
      end
    end
  end

  defp string_or_nil(_value), do: nil

  defp put_if(map, _key, nil), do: map
  defp put_if(map, _key, []), do: map
  defp put_if(map, key, value), do: Map.put(map, key, value)
end
