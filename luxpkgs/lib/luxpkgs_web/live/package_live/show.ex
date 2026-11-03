defmodule LuxpkgsWeb.PackageLive.Show do
  alias Luxpkgs.Packages
  use LuxpkgsWeb, :live_view

  import LuxpkgsWeb.Components.NotFound
  import LuxpkgsWeb.Markdown, only: [markdown: 1]

  def mount(%{"name" => name}, _session, socket) do
    case Packages.get_package_any(name) do
      nil ->
        {:ok,
         socket
         |> assign(:not_found, true)
         |> assign(:page_title, "Package not found")}

      package ->
        owner? = owner?(socket, package)

        if package.status == :active or owner? do
          {:ok,
           socket
           |> assign(:not_found, false)
           |> assign(:owner, owner?)
           |> assign(:package, Luxpkgs.Repo.preload(package, :user))
           |> assign(:page_title, package.name)}
        else
          {:ok,
           socket
           |> assign(:not_found, true)
           |> assign(:page_title, "Package not found")}
        end
    end
  end

  def handle_event("yank_release", %{"id" => id}, socket) do
    set_release_yanked(socket, id, :yank)
  end

  def handle_event("unyank_release", %{"id" => id}, socket) do
    set_release_yanked(socket, id, :unyank)
  end

  defp set_release_yanked(socket, id, action) do
    package = socket.assigns.package

    with true <- socket.assigns[:owner] || false,
         %Luxpkgs.Packages.Release{} = release <- Packages.get_release(id),
         true <- release.package_id == package.id,
         {:ok, _release} <- apply_release_action(action, socket, release) do
      package = Packages.get_package_any(package.name) |> Luxpkgs.Repo.preload(:user)

      {:noreply,
       socket
       |> assign(:package, package)
       |> put_flash(:info, if(action == :yank, do: "Release yanked.", else: "Release unyanked."))}
    else
      _ ->
        {:noreply, put_flash(socket, :error, "Could not update release.")}
    end
  end

  defp apply_release_action(:yank, socket, release) do
    Packages.yank_release(socket.assigns.current_scope, release)
  end

  defp apply_release_action(:unyank, socket, release) do
    Packages.unyank_release(socket.assigns.current_scope, release)
  end

  defp owner?(socket, package) do
    case socket.assigns[:current_scope] do
      %{user: %{id: id}} -> id == package.user_id
      _ -> false
    end
  end

  def handle_params(%{"name" => name}, _url, socket) do
    {:noreply, assign(socket, :package_name, name)}
  end

  defp format_date(date) do
    case date do
      %DateTime{} -> Calendar.strftime(date, "%B %d, %Y")
      %NaiveDateTime{} -> Calendar.strftime(date, "%B %d, %Y")
      _ -> "Unknown"
    end
  end

  defp latest_version(package) do
    case Packages.latest_release(package) do
      nil -> "-"
      release -> "v#{release.version}"
    end
  end

  defp latest_release(package), do: Packages.latest_release(package)
end
