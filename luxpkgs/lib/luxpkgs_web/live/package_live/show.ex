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
        if package.status == :active or owner?(socket, package) do
          {:ok,
           socket
           |> assign(:not_found, false)
           |> assign(:package, package |> Luxpkgs.Repo.preload(:user))
           |> assign(:page_title, package.name)}
        else
          {:ok,
           socket
           |> assign(:not_found, true)
           |> assign(:page_title, "Package not found")}
        end
    end
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

  defp latest_version([]), do: "-"

  defp latest_version(releases) do
    "v#{releases |> List.last() |> Map.get(:version)}"
  end
end
