defmodule LuxpkgsWeb.AdminLive.Users do
  use LuxpkgsWeb, :live_view

  alias Luxpkgs.Accounts
  alias Luxpkgs.Accounts.User
  alias Luxpkgs.Admin.Permissions
  alias Luxpkgs.Packages

  @impl true
  def mount(_params, _session, socket) do
    if Permissions.can?(socket.assigns.current_admin, :view_users) do
      {:ok, assign(socket, :page_title, "Users")}
    else
      {:ok,
       socket
       |> put_flash(:error, "You do not have permission to view users.")
       |> redirect(to: ~p"/admin")}
    end
  end

  @impl true
  def handle_params(params, _url, socket) do
    filters = %{
      search: String.trim(params["q"] || ""),
      status: params["status"] || "all",
      role: params["role"] || "all",
      include_deleted: params["include_deleted"] == "true",
      page: parse_page(params["page"])
    }

    {:noreply,
     socket
     |> assign(load_users(filters))
     |> assign(:filters, filters)
     |> assign(:params, params)}
  end

  @impl true
  def handle_event("filter", params, socket) do
    clean =
      params
      |> Map.take(["q", "status", "role", "include_deleted"])
      |> Enum.reject(fn {key, value} ->
        value in [nil, ""] or (key == "status" and value == "all") or
          (key == "role" and value == "all") or
          (key == "include_deleted" and value != "true")
      end)
      |> Map.new()

    {:noreply, push_patch(socket, to: ~p"/admin/users?#{clean}")}
  end

  defp load_users(filters) do
    result =
      Accounts.list_users(
        search: filters.search,
        status: filters.status,
        role: filters.role,
        include_deleted: filters.include_deleted,
        page: filters.page
      )

    users =
      Enum.map(result.users, fn user ->
        Map.put(user, :stats, Packages.owner_stats(user))
      end)

    Map.put(result, :users, users)
  end

  defp parse_page(page) do
    case Integer.parse(to_string(page || "")) do
      {number, _rest} when number > 0 -> number
      _ -> 1
    end
  end

  defp page_path(params, page) do
    "/admin/users?" <> URI.encode_query(Map.put(params, "page", page))
  end

  defp format_date(nil), do: "-"

  defp format_date(date) do
    Calendar.strftime(date, "%Y-%m-%d - %H:%M %Z")
  end

  defp admin_label(%User{admin: nil}), do: "-"

  defp admin_label(%User{admin: %{active: true, role: role}}) do
    role |> to_string() |> String.capitalize()
  end

  defp admin_label(%User{admin: %{active: false, role: role}}) do
    "#{role |> to_string() |> String.capitalize()} (inactive)"
  end

  defp suspension_badge(%User{} = user) do
    if User.suspended?(user) do
      "badge badge-warning badge-sm"
    else
      "badge badge-success badge-sm"
    end
  end

  defp suspension_label(%User{} = user) do
    if User.suspended?(user), do: "Suspended", else: "Active"
  end

  defp filtered?(filters) do
    filters.search != "" or filters.status != "all" or filters.role != "all" or
      filters.include_deleted
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin
      flash={@flash}
      current_scope={@current_scope}
      current_admin={@current_admin}
      active={:users}
    >
      <div class="space-y-6">
        <div class="flex flex-wrap items-end justify-between gap-4">
          <div>
            <h1 class="text-2xl font-bold">Users</h1>
            <p class="text-base-content/70">Review accounts and their activity.</p>
          </div>
          <div class="text-base-content/70">{@total_count} users</div>
        </div>

        <.form
          for={%{}}
          id="admin-users-filters"
          phx-change="filter"
          class="grid gap-3 md:grid-cols-[1fr_10rem_10rem_auto_auto]"
        >
          <input
            type="search"
            name="q"
            value={@filters.search}
            placeholder="Search username, email or name"
            aria-label="Search users"
            class="input input-bordered w-full bg-base-100"
          />
          <select
            name="status"
            aria-label="Filter by status"
            class="select select-bordered w-full bg-base-100"
          >
            <option value="all" selected={@filters.status == "all"}>All statuses</option>
            <option value="active" selected={@filters.status == "active"}>Active</option>
            <option value="suspended" selected={@filters.status == "suspended"}>
              Suspended
            </option>
          </select>
          <select
            name="role"
            aria-label="Filter by admin role"
            class="select select-bordered w-full bg-base-100"
          >
            <option value="all" selected={@filters.role == "all"}>All roles</option>
            <option value="admin" selected={@filters.role == "admin"}>Admin</option>
            <option value="moderator" selected={@filters.role == "moderator"}>Moderator</option>
            <option value="none" selected={@filters.role == "none"}>No admin role</option>
          </select>
          <label class="label cursor-pointer justify-start gap-2">
            <input
              type="checkbox"
              name="include_deleted"
              value="true"
              checked={@filters.include_deleted}
              class="checkbox checkbox-sm"
            />
            <span class="label-text">Include deleted</span>
          </label>
          <.link :if={filtered?(@filters)} patch={~p"/admin/users"} class="btn btn-ghost">
            <.icon name={:x} type={:outline} class="size-4" /> Clear
          </.link>
        </.form>

        <p
          :if={@users == []}
          class="rounded-box border border-base-300 bg-base-100 p-8 text-center text-sm text-base-content/70"
        >
          No users match these filters.
        </p>

        <div :if={@users != []} class="space-y-3 md:hidden">
          <article
            :for={user <- @users}
            id={"user-card-#{user.id}"}
            class="rounded-box border border-base-300 bg-base-100 p-4"
          >
            <div class="flex items-start justify-between gap-2">
              <div class="min-w-0">
                <.link
                  navigate={~p"/admin/users/#{user.id}"}
                  class="font-semibold link link-hover"
                >
                  {user.username}
                </.link>
                <p class="truncate text-sm text-base-content/70">{user.email}</p>
              </div>
              <span class={suspension_badge(user)}>{suspension_label(user)}</span>
            </div>

            <dl class="mt-4 grid grid-cols-2 gap-3 text-sm">
              <div>
                <dt class="font-semibold text-sm">ID</dt>
                <dd>{user.id}</dd>
              </div>
              <div>
                <dt class="font-semibold text-sm">Provider</dt>
                <dd>{user.provider}</dd>
              </div>
              <div>
                <dt class="font-semibold text-sm">Joined</dt>
                <dd>{format_date(user.inserted_at)}</dd>
              </div>
              <div>
                <dt class="font-semibold text-sm">Admin role</dt>
                <dd>{admin_label(user)}</dd>
              </div>
              <div>
                <dt class="font-semibold text-sm">Packages</dt>
                <dd>{format_count(user.stats.package_count)}</dd>
              </div>
              <div>
                <dt class="font-semibold text-sm">Downloads</dt>
                <dd>{format_count(user.stats.download_count)}</dd>
              </div>
            </dl>
          </article>
        </div>

        <div
          :if={@users != []}
          class="hidden overflow-x-auto rounded-box border border-base-300 bg-base-100 md:block"
        >
          <table class="table table-pin-cols table-pin-rows">
            <thead>
              <tr>
                <th>ID</th>
                <th>User</th>
                <th>Email</th>
                <th>Provider</th>
                <th>Joined</th>
                <th>Packages</th>
                <th>Downloads</th>
                <th>Admin role</th>
                <th>Status</th>
              </tr>
            </thead>
            <tbody>
              <tr :for={user <- @users} id={"user-row-#{user.id}"}>
                <td>{user.id}</td>
                <td>
                  <.link
                    navigate={~p"/admin/users/#{user.id}"}
                    class="font-semibold link link-hover"
                  >
                    {user.username}
                  </.link>
                </td>
                <td>{user.email}</td>
                <td>{user.provider}</td>
                <td>{format_date(user.inserted_at)}</td>
                <td>{format_count(user.stats.package_count)}</td>
                <td>{format_count(user.stats.download_count)}</td>
                <td>{admin_label(user)}</td>
                <td>
                  <span class={suspension_badge(user)}>{suspension_label(user)}</span>
                </td>
              </tr>
            </tbody>
          </table>
        </div>

        <div :if={@total_pages > 1} class="flex flex-wrap items-center justify-between gap-3">
          <span class="text-sm text-base-content/70">
            Page {@page} of {@total_pages}
          </span>
          <div class="join">
            <.link
              :if={@page > 1}
              patch={page_path(@params, @page - 1)}
              class="btn btn-sm join-item"
            >
              <.icon name={:chevron_left} type={:outline} class="size-4" /> Previous
            </.link>
            <span :if={@page == 1} class="btn btn-sm join-item btn-disabled">
              <.icon name={:chevron_left} type={:outline} class="size-4" /> Previous
            </span>
            <.link
              :if={@page < @total_pages}
              patch={page_path(@params, @page + 1)}
              class="btn btn-sm join-item"
            >
              Next <.icon name={:chevron_right} type={:outline} class="size-4" />
            </.link>
            <span :if={@page >= @total_pages} class="btn btn-sm join-item btn-disabled">
              Next <.icon name={:chevron_right} type={:outline} class="size-4" />
            </span>
          </div>
        </div>
      </div>
    </Layouts.admin>
    """
  end
end
