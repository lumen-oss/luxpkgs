defmodule Luxpkgs.Admin.PackageSource do
  @max_size 2 * 1024 * 1024

  alias Luxpkgs.Packages.Release

  @doc """
  Reads a release source file from the rockspec storage directory.

  Only files directly inside the configured storage directory are read.
  """
  def read(%Release{rockspec_path: path}) when is_binary(path) do
    root = storage_root()
    full_path = root |> Path.join(Path.basename(path)) |> Path.expand()

    cond do
      not String.starts_with?(full_path, root <> "/") ->
        {:error, :missing_file}

      true ->
        read_file(full_path)
    end
  end

  def read(_release), do: {:error, :missing_file}

  defp read_file(path) do
    with {:ok, %File.Stat{size: size}} when size <= @max_size <- File.stat(path),
         {:ok, content} <- File.read(path) do
      {:ok, %{filename: Path.basename(path), kind: kind(path), content: content}}
    else
      {:ok, %File.Stat{}} -> {:error, :too_large}
      {:error, _reason} -> {:error, :missing_file}
    end
  end

  defp storage_root do
    Application.get_env(:luxpkgs, :rockspec_storage)
    |> Path.expand()
  end

  defp kind(path) do
    case Path.extname(path) do
      ".toml" -> :lux_toml
      _ -> :rockspec
    end
  end
end
