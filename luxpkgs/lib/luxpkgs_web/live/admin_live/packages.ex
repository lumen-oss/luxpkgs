defmodule LuxpkgsWeb.AdminLive.Packages do
  use LuxpkgsWeb, :live_view

  alias Luxpkgs.Admin.Permissions
  alias Luxpkgs.Packages
  alias LuxpkgsWeb.AdminAuth

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
      when action in ["hide", "unhide", "remove", "restore", "feature", "unfeature"] do
    if action == "remove" and not AdminAuth.destructive_fresh?(socket) do
      {:noreply,
       socket
       |> put_flash(:error, "Verify your second factor before removing a package.")
       |> redirect(to: ~p"/admin/verify")}
    else
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
  end

  defp moderate("hide", admin, package), do: Packages.hide_package(admin, package)
  defp moderate("unhide", admin, package), do: Packages.unhide_package(admin, package)
  defp moderate("remove", admin, package), do: Packages.remove_package(admin, package)
  defp moderate("restore", admin, package), do: Packages.restore_package(admin, package)
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

  defp status_badge(:active), do: "badge badge-success badge-sm md:badge-md"
  defp status_badge(:hidden), do: "badge badge-warning badge-sm md:badge-md"
  defp status_badge(:removed), do: "badge badge-error badge-sm md:badge-md"

  defp format_date(nil), do: "-"

  defp format_date(date) do
    Calendar.strftime(date, "%Y-%m-%d - %H:%M %Z")
  end

  defp downloads(package) do
    Enum.sum(for release <- package.releases, do: release.download_count)
  end

  defp filtered?(filters) do
    filters.search != "" or filters.status != "all" or filters.featured != "all"
  end

  attr :package, :map, required: true
  attr :current_admin, :map, required: true

  defp package_actions(assigns) do
    ~H"""
    <div class="max-md:w-full flex max-md:flex-wrap justify-end gap-2">
      <button
        :if={
          @package.status in [:active, :removed] and
            Permissions.can?(@current_admin, :hide_package)
        }
        phx-click="hide"
        phx-value-id={@package.id}
        aria-label={"Hide #{@package.name}"}
        class="btn btn-warning btn-sm max-md:btn-block"
      >
        <.icon name={:eye_off} type={:outline} class="size-4" /> Hide
      </button>
      <button
        :if={
          @package.status == :hidden and
            Permissions.can?(@current_admin, :unhide_package)
        }
        phx-click="unhide"
        phx-value-id={@package.id}
        aria-label={"Unhide #{@package.name}"}
        class="btn btn-success btn-sm max-md:btn-block"
      >
        <.icon name={:eye} type={:outline} class="size-4" /> Unhide
      </button>
      <button
        :if={
          @package.status in [:active, :hidden] and
            Permissions.can?(@current_admin, :remove_package)
        }
        phx-click="remove"
        phx-value-id={@package.id}
        aria-label={"Remove #{@package.name}"}
        class="btn btn-error btn-sm max-md:btn-block"
      >
        <.icon name={:trash} type={:outline} class="size-4" /> Remove
      </button>
      <button
        :if={
          @package.status == :removed and
            Permissions.can?(@current_admin, :restore_package)
        }
        phx-click="restore"
        phx-value-id={@package.id}
        aria-label={"Restore #{@package.name}"}
        class="btn btn-success btn-sm max-md:btn-block"
      >
        <.icon name={:restore} type={:outline} class="size-4" /> Restore
      </button>
      <button
        :if={
          @package.status != :removed and
            is_nil(@package.featured_at) and
            Permissions.can?(@current_admin, :feature_package)
        }
        phx-click="feature"
        phx-value-id={@package.id}
        aria-label={"Feature #{@package.name}"}
        class="btn btn-primary btn-sm max-md:btn-block"
      >
        <.icon name={:star} type={:outline} class="size-4" /> Feature
      </button>
      <button
        :if={@package.featured_at && Permissions.can?(@current_admin, :feature_package)}
        phx-click="unfeature"
        phx-value-id={@package.id}
        aria-label={"Unfeature #{@package.name}"}
        class="btn btn-ghost btn-sm max-md:btn-block"
      >
        <.icon name={:star_off} type={:outline} class="size-4" /> Unfeature
      </button>
    </div>
    """
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin
      flash={@flash}
      current_scope={@current_scope}
      current_admin={@current_admin}
      active={:packages}
    >
      <div class="space-y-6">
        <div class="flex flex-wrap items-end justify-between gap-4">
          <div>
            <h1 class="text-2xl font-bold">Packages</h1>
            <p class="text-base-content/70">
              Review and moderate published packages.
            </p>
          </div>
          <div class="text-base-content/70">{@total_count} packages</div>
        </div>

        <.form
          for={%{}}
          id="admin-packages-filters"
          phx-change="filter"
          class="grid gap-3 md:grid-cols-[1fr_10rem_10rem_auto]"
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
            <option value="removed" selected={@filters.status == "removed"}>Removed</option>
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
          <.link :if={filtered?(@filters)} patch={~p"/admin/packages"} class="btn btn-ghost">
            <.icon name={:x} type={:outline} class="size-4" /> Clear
          </.link>
        </.form>

        <p
          :if={@packages == []}
          class="rounded-box border border-base-300 bg-base-100 p-8 text-center text-sm text-base-content/70"
        >
          No packages match these filters.
        </p>

        <div :if={@packages != []} class="space-y-3 md:hidden">
          <article
            :for={package <- @packages}
            id={"package-card-#{package.id}"}
            class="rounded-box border border-base-300 bg-base-100 p-4"
          >
            <div class="flex flex-col justify-between gap-2">
              <div class="flex items-center justify-between">
                <.link
                  navigate={~p"/admin/packages/#{package.id}"}
                  class="font-semibold link link-hover"
                >
                  {package.name}
                </.link>
                <div class="flex justify-end gap-2">
                  <span :if={package.featured_at} class="badge badge-primary badge-sm">
                    Featured
                  </span>
                  <span class={status_badge(package.status)}>{package.status}</span>
                </div>
              </div>
              <p class="mt-1 line-clamp-2 text-sm text-base-content/70">
                {package.summary}
              </p>
            </div>

            <dl class="mt-4 grid grid-cols-2 gap-3 text-sm">
              <div>
                <dt class="font-semibold text-sm">Owner</dt>
                <dd class="truncate">{package.user.username}</dd>
              </div>
              <div>
                <dt class="font-semibold text-sm">Releases</dt>
                <dd>{length(package.releases)}</dd>
              </div>
              <div>
                <dt class="font-semibold text-sm">Downloads</dt>
                <dd>{format_count(downloads(package))}</dd>
              </div>
              <div>
                <dt class="font-semibold text-sm">Updated</dt>
                <dd>{format_date(package.updated_at)}</dd>
              </div>
            </dl>

            <div class="mt-4 flex flex-wrap items-center gap-2">
              <.package_actions package={package} current_admin={@current_admin} />
            </div>
          </article>
        </div>

        <div
          :if={@packages != []}
          class="hidden overflow-x-auto rounded-box border border-base-300 bg-base-100 md:block"
        >
          <table class="table table-pin-cols table-pin-rows">
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
              <tr :for={package <- @packages} id={"package-row-#{package.id}"}>
                <td>
                  <.link
                    navigate={~p"/admin/packages/#{package.id}"}
                    class="font-semibold link link-hover"
                  >
                    {package.name}
                  </.link>
                  <div class="max-w-xs truncate text-xs text-base-content/70">
                    {package.summary}
                  </div>
                </td>
                <td>{package.user.username}</td>
                <td>
                  <span class={status_badge(package.status)}>{package.status}</span>
                </td>
                <td>
                  <span :if={package.featured_at} class="badge badge-primary">
                    Featured
                  </span>
                  <span :if={is_nil(package.featured_at)}>-</span>
                </td>
                <td>{length(package.releases)}</td>
                <td>{format_count(downloads(package))}</td>
                <td>{format_date(package.updated_at)}</td>
                <td class="whitespace-nowrap text-right">
                  <.package_actions package={package} current_admin={@current_admin} />
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
