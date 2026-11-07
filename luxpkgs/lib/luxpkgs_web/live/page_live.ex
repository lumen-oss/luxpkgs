defmodule LuxpkgsWeb.PageLive do
  alias Luxpkgs.Packages
  alias Luxpkgs.Accounts
  use LuxpkgsWeb, :live_view

  import LuxpkgsWeb.PackageBox

  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:packages, Packages.list_packages(:exact, "", []) |> Map.get(:packages))
     |> assign(:featured, featured_packages())
     |> assign(:active_users, Accounts.user_count())}
  end

  defp featured_packages do
    case Packages.list_featured(4) do
      [] -> Packages.list_popular(4)
      packages -> packages
    end
  end
end
