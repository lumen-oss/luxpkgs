defmodule LuxpkgsWeb.AdminNav do
  @moduledoc """
  Shared navigation for the admin area.

  The same destinations are rendered as a sidebar on desktop and a dock on
  mobile, so labels and active state cannot drift between layouts.
  """

  use LuxpkgsWeb, :html

  alias Luxpkgs.Admin.Permissions

  attr :active, :atom, required: true
  attr :variant, :atom, values: [:sidebar, :dock], required: true
  attr :current_admin, :map, default: nil

  def nav(assigns) do
    ~H"""
    <nav class={nav_class(@variant)} aria-label="Admin">
      <.link
        :for={item <- items(@current_admin)}
        navigate={item.path}
        class={item_class(@variant, item.key, @active)}
        aria-current={if(item.key == @active, do: "page", else: nil)}
      >
        <.icon name={item.icon} type={:outline} class={icon_class(@variant)} />
        <span class={label_class(@variant)}>{item.label}</span>
      </.link>
    </nav>
    """
  end

  defp items(current_admin) do
    [
      %{
        key: :dashboard,
        label: "Dashboard",
        path: "/admin",
        icon: :shield_check,
        permission: :view_dashboard
      },
      %{
        key: :packages,
        label: "Packages",
        path: "/admin/packages",
        icon: :package,
        permission: :view_packages
      },
      %{
        key: :reports,
        label: "Reports",
        path: "/admin/reports",
        icon: :alert_triangle,
        permission: :view_reports
      },
      %{
        key: :users,
        label: "Users",
        path: "/admin/users",
        icon: :users,
        permission: :view_users
      },
      %{
        key: :audit,
        label: "Audit",
        path: "/admin/audit",
        icon: :file_text,
        permission: :view_audit
      },
      %{key: :site, label: "Site", path: "/", icon: :arrow_left, permission: nil}
    ]
    |> Enum.filter(fn
      %{permission: nil} -> true
      %{permission: permission} -> Permissions.can?(current_admin, permission)
    end)
  end

  defp nav_class(:sidebar), do: "menu w-full flex-1 gap-1 p-4"

  defp nav_class(:dock) do
    "dock md:hidden fixed inset-x-0 bottom-0 z-40 border-t border-base-300 bg-base-100 pb-[env(safe-area-inset-bottom)]"
  end

  defp item_class(:sidebar, key, active) do
    base = "flex items-center gap-3 rounded-box px-3 py-2 text-sm font-medium transition-colors"

    if key == active do
      base <> " bg-primary text-primary-content"
    else
      base <> " hover:bg-base-100"
    end
  end

  defp item_class(:dock, key, active) do
    if key == active, do: "dock-active", else: ""
  end

  defp icon_class(:sidebar), do: "size-4"
  defp icon_class(:dock), do: "size-5"

  defp label_class(:sidebar), do: nil
  defp label_class(:dock), do: "dock-label"
end
