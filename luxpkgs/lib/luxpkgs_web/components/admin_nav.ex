defmodule LuxpkgsWeb.AdminNav do
  @moduledoc """
  Shared navigation for the admin area.

  The same destinations are rendered as a sidebar on desktop and a dock on
  mobile, so labels and active state cannot drift between layouts.
  """

  use LuxpkgsWeb, :html

  attr :active, :atom, required: true
  attr :variant, :atom, values: [:sidebar, :dock], required: true

  def nav(assigns) do
    ~H"""
    <nav class={nav_class(@variant)} aria-label="Admin">
      <.link
        :for={item <- items()}
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

  defp items do
    [
      %{key: :dashboard, label: "Dashboard", path: "/admin", icon: :shield_check},
      %{key: :packages, label: "Packages", path: "/admin/packages", icon: :package},
      %{key: :reports, label: "Reports", path: "/admin/reports", icon: :alert_triangle},
      %{key: :site, label: "Site", path: "/", icon: :arrow_left}
    ]
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
