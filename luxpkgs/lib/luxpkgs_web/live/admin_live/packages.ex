defmodule LuxpkgsWeb.AdminLive.Packages do
  use LuxpkgsWeb, :live_view

  alias Luxpkgs.Admin.Permissions
  alias Luxpkgs.Packages

  @impl true
  def mount(_params, _session, socket) do
    if Permissions.can?(socket.assigns.current_admin, :view_packages) do
      {:ok, assign(socket, :page_title, "Packages")}
    else
      {:ok,
       socket
       |> put_flash(:error, "You do not have permission to view packages.")
       |> redirect(to: ~p"/admin")}
    end
  end

  @impl true
  def handle_params(params, _url, socket) do
    filters = %{
      search: String.trim(params["q"] || ""),
      status: params["status"] || "all",
      featured: params["featured"] || "all",
      page: parse_page(params["page"])
    }

    {:noreply,
     socket
     |> assign(load_packages(filters))
     |> assign(:filters, filters)
     |> assign(:params, params)}
  end

  @impl true
  def handle_event("filter", params, socket) do
    clean =
      params
      |> Map.take(["q", "status", "featured"])
      |> Enum.reject(fn {key, value} ->
        value in [nil, ""] or (key == "status" and value == "all") or
          (key == "featured" and value == "all")
      end)
      |> Map.new()

    {:noreply, push_patch(socket, to: ~p"/admin/packages?#{clean}")}
  end

  def handle_event(action, %{"id" => id}, socket)
      when action in ["hide", "unhide", "feature", "unfeature"] do
    package = Packages.get_package_by_id(id)

    case moderate(action, socket.assigns.current_admin, package) do
      {:ok, _package} ->
        {:noreply,
         socket
         |> put_flash(:info, "Package updated.")
         |> assign(load_packages(socket.assigns.filters))}

      {:error, :insufficient_permissions} ->
        {:noreply, put_flash(socket, :error, "You do not have permission to do that.")}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Could not update the package.")}
    end
  end

  defp moderate("hide", admin, package), do: Packages.hide_package(admin, package)
  defp moderate("unhide", admin, package), do: Packages.unhide_package(admin, package)
  defp moderate("feature", admin, package), do: Packages.feature_package(admin, package)
  defp moderate("unfeature", admin, package), do: Packages.unfeature_package(admin, package)

  defp load_packages(filters) do
    Packages.list_packages_admin(
      search: filters.search,
      status: filters.status,
      featured: filters.featured,
      page: filters.page
    )
  end

  defp parse_page(page) do
    case Integer.parse(to_string(page || "")) do
      {number, _rest} when number > 0 -> number
      _ -> 1
    end
  end

  defp page_path(params, page) do
    "/admin/packages?" <> URI.encode_query(Map.put(params, "page", page))
  end

  defp status_badge(:active), do: "badge badge-success badge-sm"
  defp status_badge(:hidden), do: "badge badge-warning badge-sm"

  defp format_date(nil), do: "-"

  defp format_date(date) do
    Calendar.strftime(date, "%Y-%m-%d")
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin flash={@flash} current_scope={@current_scope} current_admin={@current_admin}>
      <div class="space-y-6">
        <div class="flex flex-wrap items-end justify-between gap-4">
          <div>
            <h1 class="text-2xl font-bold">Packages</h1>
            <p class="text-sm text-base-content/70">
              Review and moderate published packages.
            </p>
          </div>
          <div class="text-sm text-base-content/70">{@total_count} packages</div>
        </div>

        <.form
          for={%{}}
          id="admin-packages-filters"
          phx-change="filter"
          class="grid gap-3 sm:grid-cols-[1fr_10rem_10rem]"
        >
          <input
            type="search"
            name="q"
            value={@filters.search}
            placeholder="Search name, summary or owner"
            aria-label="Search packages"
            class="input input-bordered w-full bg-base-100"
          />
          <select
            name="status"
            aria-label="Filter by status"
            class="select select-bordered w-full bg-base-100"
          >
            <option value="all" selected={@filters.status == "all"}>All statuses</option>
            <option value="active" selected={@filters.status == "active"}>Active</option>
            <option value="hidden" selected={@filters.status == "hidden"}>Hidden</option>
          </select>
          <select
            name="featured"
            aria-label="Filter by featured"
            class="select select-bordered w-full bg-base-100"
          >
            <option value="all" selected={@filters.featured == "all"}>All packages</option>
            <option value="true" selected={@filters.featured == "true"}>Featured</option>
            <option value="false" selected={@filters.featured == "false"}>Not featured</option>
          </select>
        </.form>

        <div class="overflow-x-auto rounded-box border border-base-300 bg-base-100">
          <table class="table">
            <thead>
              <tr>
                <th>Package</th>
                <th>Owner</th>
                <th>Status</th>
                <th>Featured</th>
                <th>Releases</th>
                <th>Downloads</th>
                <th>Updated</th>
                <th></th>
              </tr>
            </thead>
            <tbody>
              <tr :for={package <- @packages}>
                <td>
                  <.link
                    navigate={~p"/admin/packages/#{package.id}"}
                    class="font-semibold link link-hover"
                  >
                    {package.name}
                  </.link>
                  <div class="max-w-xs truncate text-xs text-base-content/60">
                    {package.summary}
                  </div>
                </td>
                <td>{package.user.username}</td>
                <td>
                  <span class={status_badge(package.status)}>{package.status}</span>
                </td>
                <td>
                  <span :if={package.featured_at} class="badge badge-primary badge-sm">
                    Featured
                  </span>
                  <span :if={is_nil(package.featured_at)}>-</span>
                </td>
                <td>{length(package.releases)}</td>
                <td>{format_count(Enum.sum(for r <- package.releases, do: r.download_count))}</td>
                <td>{format_date(package.updated_at)}</td>
                <td class="whitespace-nowrap text-right">
                  <div class="flex justify-end gap-2">
                    <button
                      :if={
                        package.status == :active and
                          Permissions.can?(@current_admin, :hide_package)
                      }
                      phx-click="hide"
                      phx-value-id={package.id}
                      class="btn btn-xs btn-warning"
                    >
                      Hide
                    </button>
                    <button
                      :if={
                        package.status == :hidden and
                          Permissions.can?(@current_admin, :unhide_package)
                      }
                      phx-click="unhide"
                      phx-value-id={package.id}
                      class="btn btn-xs btn-success"
                    >
                      Unhide
                    </button>
                    <button
                      :if={
                        is_nil(package.featured_at) and
                          Permissions.can?(@current_admin, :feature_package)
                      }
                      phx-click="feature"
                      phx-value-id={package.id}
                      class="btn btn-xs btn-primary"
                    >
                      Feature
                    </button>
                    <button
                      :if={package.featured_at && Permissions.can?(@current_admin, :feature_package)}
                      phx-click="unfeature"
                      phx-value-id={package.id}
                      class="btn btn-xs btn-ghost"
                    >
                      Unfeature
                    </button>
                  </div>
                </td>
              </tr>
            </tbody>
          </table>

          <div :if={@packages == []} class="p-10 text-center text-base-content/70">
            No packages match these filters.
          </div>
        </div>

        <div class="flex items-center justify-between">
          <span class="text-sm text-base-content/70">
            Page {@page} of {@total_pages}
          </span>
          <div class="join">
            <.link
              :if={@page > 1}
              patch={page_path(@params, @page - 1)}
              class="btn btn-sm join-item"
            >
              Previous
            </.link>
            <.link
              :if={@page < @total_pages}
              patch={page_path(@params, @page + 1)}
              class="btn btn-sm join-item"
            >
              Next
            </.link>
          </div>
        </div>
      </div>
    </Layouts.admin>
    """
  end
end
