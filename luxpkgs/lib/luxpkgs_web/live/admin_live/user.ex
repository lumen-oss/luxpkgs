defmodule LuxpkgsWeb.AdminLive.User do
  use LuxpkgsWeb, :live_view

  alias Luxpkgs.Accounts
  alias Luxpkgs.Accounts.User
  alias Luxpkgs.Admin.Permissions
  alias Luxpkgs.Audit
  alias Luxpkgs.Audit.Catalog
  alias Luxpkgs.Moderation
  alias Luxpkgs.Packages
  alias Luxpkgs.Repo
  alias LuxpkgsWeb.AdminAuth
  alias LuxpkgsWeb.UserAuth

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    if Permissions.can?(socket.assigns.current_admin, :view_users) do
      case load_user(id) do
        nil ->
          {:ok, assign(socket, not_found: true, page_title: "User not found")}

        user ->
          {:ok,
           socket
           |> assign(page_title: "#{user.username} · Admin", not_found: false)
           |> assign_user(user)}
      end
    else
      {:ok,
       socket
       |> put_flash(:error, "You do not have permission to view users.")
       |> redirect(to: ~p"/admin")}
    end
  end

  @impl true
  def handle_event("suspend", %{"reason" => reason}, socket) do
    if AdminAuth.destructive_fresh?(socket) do
      case Accounts.suspend_user(socket.assigns.current_admin, socket.assigns.user, reason) do
        {:ok, user, tokens} ->
          UserAuth.disconnect_sessions(tokens)
          finish_suspension(socket, user, "User suspended.")

        {:error, reason} ->
          {:noreply, put_flash(socket, :error, suspension_error(reason))}
      end
    else
      {:noreply,
       socket
       |> put_flash(:error, "Verify your second factor before suspending a user.")
       |> redirect(to: ~p"/admin/verify")}
    end
  end

  def handle_event("unsuspend", _params, socket) do
    case Accounts.unsuspend_user(socket.assigns.current_admin, socket.assigns.user) do
      {:ok, user} ->
        finish_suspension(socket, user, "User unsuspended.")

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Could not update the user.")}
    end
  end

  defp finish_suspension(socket, user, message) do
    user = Repo.preload(user, :admin)

    {:noreply,
     socket
     |> push_event("close_dialog", %{id: "suspend_user_modal"})
     |> put_flash(:info, message)
     |> assign_user(user)}
  end

  defp assign_user(socket, user) do
    assign(socket,
      user: user,
      stats: Packages.owner_stats(user),
      report_count: Moderation.count_reports_by_user(user),
      packages: Packages.list_packages_by_user(user),
      events: Audit.list_events(target_type: "user", target_id: user.id, limit: 50)
    )
  end

  defp suspension_error(:self_suspend), do: "You cannot suspend your own account."

  defp suspension_error(:last_admin),
    do: "The last active admin cannot be suspended."

  defp suspension_error(_reason),
    do: "Check the suspension reason and try again."

  defp load_user(id) do
    case Integer.parse(to_string(id)) do
      {user_id, ""} when user_id > 0 ->
        case Accounts.get_user(user_id) do
          %User{} = user -> Repo.preload(user, :admin)
          nil -> nil
        end

      _ ->
        nil
    end
  end

  defp format_date(nil), do: "-"

  defp format_date(date) do
    Calendar.strftime(date, "%Y-%m-%d - %H:%M %Z")
  end

  defp status_badge(:active), do: "badge badge-success badge-sm"
  defp status_badge(:hidden), do: "badge badge-warning badge-sm"
  defp status_badge(:removed), do: "badge badge-error badge-sm"

  defp admin_label(%User{admin: nil}), do: "No admin role"

  defp admin_label(%User{admin: %{active: true, role: role}}) do
    role |> to_string() |> String.capitalize()
  end

  defp admin_label(%User{admin: %{active: false, role: role}}) do
    "#{role |> to_string() |> String.capitalize()} (inactive)"
  end

  defp suspension_badge(%User{} = user) do
    if User.suspended?(user),
      do: "badge badge-warning",
      else: "badge badge-success"
  end

  defp suspension_label(%User{} = user) do
    if User.suspended?(user), do: "Suspended", else: "Active"
  end

  defp downloads(package) do
    Enum.sum(for release <- package.releases, do: release.download_count)
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
      <div
        :if={@not_found}
        class="mx-auto max-w-lg rounded-box border border-base-300 bg-base-100 p-8 text-center"
      >
        <h1 class="text-xl font-bold">User not found</h1>
        <p class="mt-2 text-base-content/70">
          This account does not exist or was deleted.
        </p>
        <.link navigate={~p"/admin/users"} class="btn btn-primary mt-4">Back to users</.link>
      </div>

      <div :if={!@not_found} class="space-y-6">
        <.link navigate={~p"/admin/users"} class="link link-hover text-sm">
          ← Back to users
        </.link>

        <div class="flex flex-wrap items-start justify-between gap-4">
          <div class="flex items-center gap-3">
            <img
              :if={@user.avatar_url}
              src={@user.avatar_url}
              alt=""
              class="size-12 rounded-full"
            />
            <div>
              <h1 class="text-2xl font-bold">{@user.username}</h1>
              <p class="text-base-content/70">{@user.email}</p>
            </div>
          </div>
          <div class="flex flex-wrap items-center gap-2">
            <span class={suspension_badge(@user)}>{suspension_label(@user)}</span>
            <span class="badge badge-ghost">{@user.provider}</span>
          </div>
        </div>

        <div class="grid gap-4 md:grid-cols-3">
          <div class="rounded-box border border-base-300 bg-base-100 p-4">
            <p class="text-sm text-base-content/70">Packages</p>
            <p class="text-2xl font-bold">{format_count(@stats.package_count)}</p>
          </div>
          <div class="rounded-box border border-base-300 bg-base-100 p-4">
            <p class="text-sm text-base-content/70">Total downloads</p>
            <p class="text-2xl font-bold">{format_count(@stats.download_count)}</p>
          </div>
          <div class="rounded-box border border-base-300 bg-base-100 p-4">
            <p class="text-sm text-base-content/70">Reports filed</p>
            <p class="text-2xl font-bold">{format_count(@report_count)}</p>
          </div>
        </div>

        <div class="grid gap-4 md:grid-cols-2">
          <section class="rounded-box border border-base-300 bg-base-100 p-4">
            <h2 class="text-lg font-semibold">Profile</h2>
            <dl class="mt-3 grid grid-cols-2 gap-3 text-sm">
              <div>
                <dt class="font-semibold">ID</dt>
                <dd>{@user.id}</dd>
              </div>
              <div>
                <dt class="font-semibold">Provider</dt>
                <dd>{@user.provider}</dd>
              </div>
              <div>
                <dt class="font-semibold">Joined</dt>
                <dd>{format_date(@user.inserted_at)}</dd>
              </div>
              <div>
                <dt class="font-semibold">Admin role</dt>
                <dd>{admin_label(@user)}</dd>
              </div>
              <div class="col-span-2">
                <dt class="font-semibold">Bio</dt>
                <dd>{@user.bio || "-"}</dd>
              </div>
            </dl>
          </section>

          <section class="rounded-box border border-base-300 bg-base-100 p-4">
            <h2 class="text-lg font-semibold">Suspension</h2>
            <dl :if={User.suspended?(@user)} class="mt-3 grid grid-cols-2 gap-3 text-sm">
              <div>
                <dt class="font-semibold">Since</dt>
                <dd>{format_date(@user.suspended_at)}</dd>
              </div>
              <div class="col-span-2">
                <dt class="font-semibold">Reason</dt>
                <dd>{@user.suspension_reason}</dd>
              </div>
            </dl>
            <p :if={!User.suspended?(@user)} class="mt-3 text-sm text-base-content/70">
              This account is active.
            </p>

            <button
              :if={!User.suspended?(@user)}
              type="button"
              onclick="suspend_user_modal.showModal()"
              disabled={@current_admin.user_id == @user.id}
              class="btn btn-error btn-sm mt-3"
            >
              Suspend user
            </button>

            <p
              :if={!User.suspended?(@user) and @current_admin.user_id == @user.id}
              class="mt-3 text-sm text-base-content/70"
            >
              You cannot suspend your own account.
            </p>

            <.confirm_modal
              :if={!User.suspended?(@user)}
              id="suspend_user_modal"
              title="Suspend user?"
              form={%{}}
              form_id="suspend-user-form"
              submit="suspend"
            >
              <p class="text-sm text-base-content/80">
                Suspending this user ends their sessions and API access. Their packages stay active.
              </p>
              <textarea
                name="reason"
                rows="3"
                required
                disabled={@current_admin.user_id == @user.id}
                placeholder="Reason for suspension"
                aria-label="Suspension reason"
                class="textarea textarea-bordered w-full bg-base-100"
              ></textarea>
              <:confirm>
                <button
                  type="submit"
                  class="btn btn-error"
                  disabled={@current_admin.user_id == @user.id}
                >
                  Suspend user
                </button>
              </:confirm>
            </.confirm_modal>

            <button
              :if={User.suspended?(@user)}
              type="button"
              phx-click="unsuspend"
              class="btn btn-primary btn-sm mt-3"
            >
              Unsuspend user
            </button>
          </section>
        </div>

        <section class="rounded-box border border-base-300 bg-base-100">
          <div class="border-b border-base-300 p-4">
            <h2 class="text-lg font-semibold">Packages</h2>
          </div>
          <p :if={@packages == []} class="p-4 text-sm text-base-content/70">
            This user has no packages.
          </p>
          <div :if={@packages != []} class="overflow-x-auto">
            <table class="table">
              <thead>
                <tr>
                  <th>Package</th>
                  <th>Status</th>
                  <th>Releases</th>
                  <th>Downloads</th>
                  <th>Updated</th>
                </tr>
              </thead>
              <tbody>
                <tr :for={package <- @packages} id={"user-package-row-#{package.id}"}>
                  <td>
                    <.link
                      navigate={~p"/admin/packages/#{package.id}"}
                      class="font-semibold link link-hover"
                    >
                      {package.name}
                    </.link>
                  </td>
                  <td>
                    <span class={status_badge(package.status)}>{package.status}</span>
                  </td>
                  <td>{length(package.releases)}</td>
                  <td>{format_count(downloads(package))}</td>
                  <td>{format_date(package.updated_at)}</td>
                </tr>
              </tbody>
            </table>
          </div>
        </section>

        <section class="rounded-box border border-base-300 bg-base-100">
          <div class="border-b border-base-300 p-4">
            <h2 class="text-lg font-semibold">Audit events</h2>
          </div>
          <p :if={@events == []} class="p-4 text-sm text-base-content/70">
            No audit events for this user.
          </p>
          <ul :if={@events != []} class="divide-y divide-base-300">
            <li :for={event <- @events} class="flex flex-wrap items-baseline gap-2 p-4 text-sm">
              <span class="text-base-content/70">{format_date(event.inserted_at)}</span>
              <span class="font-medium">{Catalog.label(event.action)}</span>
              <span class="text-base-content/70">by {event.actor_label}</span>
              <span :if={event.metadata["reason"]} class="text-base-content/70">
                Reason: {event.metadata["reason"]}
              </span>
            </li>
          </ul>
        </section>
      </div>
    </Layouts.admin>
    """
  end
end
