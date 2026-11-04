defmodule LuxpkgsWeb.AdminLive.Dashboard do
  use LuxpkgsWeb, :live_view

  alias Luxpkgs.Accounts
  alias Luxpkgs.Admin
  alias Luxpkgs.Admin.Permissions
  alias Luxpkgs.Audit
  alias Luxpkgs.Packages

  @impl true
  def mount(_params, _session, socket) do
    can_view_audit = Permissions.can?(socket.assigns.current_admin, :view_audit)

    stats =
      Packages.admin_stats()
      |> Map.put(:users, Accounts.user_count())
      |> Map.put(:active_admins, Admin.active_count())

    recent_events = if can_view_audit, do: Audit.list_events(10), else: []

    {:ok,
     assign(socket,
       page_title: "Dashboard",
       stats: stats,
       recent_events: recent_events,
       can_view_audit: can_view_audit
     )}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin
      flash={@flash}
      current_scope={@current_scope}
      current_admin={@current_admin}
      active={:dashboard}
    >
      <div class="space-y-6">
        <div>
          <h1 class="text-2xl font-bold">Dashboard</h1>
          <p class="text-base-content/70">
            Overview of packages, releases and moderation activity.
          </p>
        </div>

        <div class="grid gap-4 grid-cols-2 xl:grid-cols-4">
          <.stat_card
            label="Packages"
            value={to_string(@stats.packages)}
            detail={"#{@stats.active_packages} active, #{@stats.hidden_packages} hidden"}
            icon={:package}
          />
          <.stat_card
            label="Releases"
            value={to_string(@stats.releases)}
            detail={"#{@stats.yanked_releases} yanked"}
            icon={:tag}
          />
          <.stat_card
            label="Downloads"
            value={format_count(@stats.downloads)}
            detail="All time"
            icon={:download}
          />
          <.stat_card
            label="Users"
            value={to_string(@stats.users)}
            detail={"#{@stats.active_admins} active admins"}
            icon={:users}
          />
        </div>

        <div>
          <section
            :if={@can_view_audit}
            class="rounded-box border border-base-300 bg-base-100"
          >
            <header class="flex items-center justify-between gap-3 border-b border-base-300 p-4">
              <div>
                <h2 class="text-lg font-semibold">Recent activity</h2>
                <p class="text-sm text-base-content/60">Latest admin actions.</p>
              </div>
              <div class="mr-1 rounded-box bg-base-content/10 p-2">
                <.icon name={:clock} type={:outline} class="size-5 text-base-content/50" />
              </div>
            </header>

            <p :if={@recent_events == []} class="p-6 text-sm text-base-content/70">
              No admin activity yet.
            </p>

            <ul :if={@recent_events != []} class="divide-y divide-base-300">
              <li :for={event <- @recent_events} class="flex gap-3 p-4">
                <div class="min-w-0">
                  <span class="max-md:text-sm font-medium">{event.actor_label || "System"}</span>
                  <span class="max-md:text-sm font-bold">{action_label(event.action)}</span>
                  <span class="max-md:text-sm text-base-content/70">{event.target_label}</span>
                  <p class="mt-1 text-xs md:text-sm text-base-content/70">
                    {format_datetime(event.inserted_at)}
                  </p>
                </div>
              </li>
            </ul>
          </section>
        </div>
      </div>
    </Layouts.admin>
    """
  end

  attr :label, :string, required: true
  attr :value, :string, required: true
  attr :detail, :string, default: nil
  attr :icon, :atom, required: true

  defp stat_card(assigns) do
    ~H"""
    <div class="rounded-box border border-base-300 bg-base-100 p-4">
      <div class="flex flex-col items-start justify-between">
        <div class="flex items-start justify-between w-full">
          <p class="text-lg md:text-xl font-semibold text-base-content">{@label}</p>
          <div class="rounded-box bg-primary/10 p-1 md:p-2">
            <.icon name={@icon} type={:outline} class="size-6 md:size-6 shrink-0 text-primary/70" />
          </div>
        </div>
        <div class="min-w-0">
          <p class="my-1 text-3xl font-bold text-primary">{@value}</p>
          <p :if={@detail} class="text-sm text-base-content/70">{@detail}</p>
        </div>
      </div>
    </div>
    """
  end

  defp action_label("package.hidden"), do: "hid"
  defp action_label("package.unhidden"), do: "unhid"
  defp action_label("package.featured"), do: "featured"
  defp action_label("package.unfeatured"), do: "unfeatured"
  defp action_label("release.yanked"), do: "yanked"
  defp action_label("release.unyanked"), do: "unyanked"
  defp action_label(action), do: action

  defp format_datetime(nil), do: "-"
  defp format_datetime(datetime), do: Calendar.strftime(datetime, "%H:%M %Z, %a, %B %d, %Y")
end
