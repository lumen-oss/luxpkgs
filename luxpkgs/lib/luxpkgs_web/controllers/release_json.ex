defmodule LuxpkgsWeb.ReleaseJSON do
  alias Luxpkgs.Packages.Release

  @doc """
  Renders a list of releases.
  """
  def index(%{releases: releases}) do
    %{data: for(release <- releases, do: data(release))}
  end

  @doc """
  Renders a single release.
  """
  def show(%{release: release}) do
    %{data: data(release)}
  end

  defp data(%Release{} = release) do
    %{
      id: release.id,
      version: to_string(release.version),
      yanked: release.yanked_at != nil
    }
  end
end
