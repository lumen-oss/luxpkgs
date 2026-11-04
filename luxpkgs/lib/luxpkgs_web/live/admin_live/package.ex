defmodule LuxpkgsWeb.AdminLive.Package do
  use LuxpkgsWeb, :live_view

  alias Luxpkgs.Admin.PackageSource
  alias Luxpkgs.Admin.Permissions
  alias Luxpkgs.Packages
  alias LuxpkgsWeb.Admin.SourceHighlighter
  alias Luxpkgs.Packages.Package, as: PackageSchema
  alias Luxpkgs.Repo

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    if Permissions.can?(socket.assigns.current_admin, :view_package) do
      case Packages.get_package_by_id(id) do
        nil ->
          {:ok,
           socket
           |> assign(:not_found, true)
           |> assign(:page_title, "Package not found")}

        %PackageSchema{} = package ->
          package = Repo.preload(package, :user)
          selected = List.last(package.releases)

          {:ok,
           socket
           |> assign(:not_found, false)
           |> assign(:package, package)
           |> assign(:selected_release, selected)
           |> assign_source(selected)
           |> assign(:page_title, "#{package.name} · Admin")}
      end
    else
      {:ok,
       socket
       |> put_flash(:error, "You do not have permission to view packages.")
       |> redirect(to: ~p"/admin")}
    end
  end

  @impl true
  def handle_event("select_release", %{"release" => id}, socket) do
    case Enum.find(socket.assigns.package.releases, &(to_string(&1.id) == id)) do
      nil -> {:noreply, socket}
      release -> {:noreply, select_release(socket, release)}
    end
  end

  def handle_event("navigate_release", %{"direction" => direction}, socket)
      when direction in ["prev", "next"] do
    releases = socket.assigns.package.releases
    current = socket.assigns.selected_release
    index = Enum.find_index(releases, &(&1.id == current.id)) || 0
    target_index = if direction == "prev", do: index - 1, else: index + 1

    case Enum.at(releases, target_index) do
      nil -> {:noreply, socket}
      release -> {:noreply, select_release(socket, release)}
    end
  end

  def handle_event("moderate", %{"action" => action}, socket)
      when action in ["hide", "unhide", "feature", "unfeature"] do
    package = Packages.get_package_by_id(socket.assigns.package.id)

    case moderate(action, socket.assigns.current_admin, package) do
      {:ok, _package} ->
        {:noreply,
         socket
         |> put_flash(:info, "Package updated.")
         |> reload_package()}

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

  defp reload_package(socket) do
    package =
      Packages.get_package_by_id(socket.assigns.package.id)
      |> Repo.preload(:user)

    selected =
      Enum.find(package.releases, &(&1.id == socket.assigns.selected_release.id)) ||
        List.last(package.releases)

    socket
    |> assign(:package, package)
    |> assign(:selected_release, selected)
    |> assign_source(selected)
  end

  defp select_release(socket, release) do
    socket
    |> assign(:selected_release, release)
    |> assign_source(release)
  end

  defp read_source(nil), do: {:error, :no_release}
  defp read_source(release), do: PackageSource.read(release)

  defp assign_source(socket, release) do
    source = read_source(release)

    source_lines =
      case source do
        {:ok, %{content: content, kind: kind}} -> SourceHighlighter.lines(content, kind)
        _ -> []
      end

    assign(socket, source: source, source_lines: source_lines)
  end

  defp kind_label(:rockspec), do: "rockspec"
  defp kind_label(:lux_toml), do: "lux.toml"
  defp kind_label(_kind), do: "source"

  defp error_label(:no_release), do: "This package has no releases."
  defp error_label(:too_large), do: "The source file is larger than 2 MB."
  defp error_label(:unreadable), do: "The source file could not be read."
  defp error_label(_reason), do: "The source file is missing."

  defp render_source_lines(lines) do
    lines
    |> Enum.with_index(1)
    |> Enum.map_join(fn {tokens, index} ->
      ~s(<span data-ln="#{index}" class="source-line">#{render_tokens(tokens)}</span>)
    end)
    |> Phoenix.HTML.raw()
  end

  defp render_tokens(tokens) do
    Enum.map_join(tokens, fn {type, text} ->
      escaped = text |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()

      case token_class(type) do
        nil -> escaped
        class -> ~s(<span class="#{class}">#{escaped}</span>)
      end
    end)
  end

  defp token_class(:comment), do: "text-base-content/40 italic"
  defp token_class(:string), do: "text-success"
  defp token_class(:number), do: "text-warning"
  defp token_class(:keyword), do: "text-primary"
  defp token_class(:operator), do: "text-accent"
  defp token_class(_type), do: nil

  defp status_badge(:active), do: "badge badge-success badge-sm"
  defp status_badge(:hidden), do: "badge badge-warning badge-sm"

  defp format_date(nil), do: "-"
  defp format_date(date), do: Calendar.strftime(date, "%Y-%m-%d %H:%M")

  defp selected_index(package, release) do
    Enum.find_index(package.releases, &(&1.id == release.id)) || 0
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin flash={@flash} current_scope={@current_scope} current_admin={@current_admin}>
      <%= if @not_found do %>
        <div class="rounded-box border border-base-300 bg-base-100 p-10 text-center">
          <h1 class="text-xl font-semibold">Package not found</h1>
          <p class="mt-2 text-base-content/70">This package no longer exists.</p>
          <.link navigate={~p"/admin/packages"} class="btn btn-sm mt-6">Back to packages</.link>
        </div>
      <% else %>
        <div id="admin-package-viewer" phx-hook="ReleaseNavigation" class="space-y-6">
          <div>
            <.link navigate={~p"/admin/packages"} class="link link-hover text-sm">
              ← Back to packages
            </.link>
          </div>

          <div class="flex flex-wrap items-start justify-between gap-4">
            <div>
              <div class="flex flex-wrap items-center gap-3">
                <h1 class="text-2xl font-bold">{@package.name}</h1>
                <span class={status_badge(@package.status)}>{@package.status}</span>
                <span :if={@package.featured_at} class="badge badge-primary badge-sm">
                  Featured
                </span>
              </div>
              <p class="mt-1 text-sm text-base-content/70">
                by {@package.user.username} · created {format_date(@package.inserted_at)}
              </p>
            </div>

            <div class="flex flex-wrap gap-2">
              <button
                :if={@package.status == :active and Permissions.can?(@current_admin, :hide_package)}
                phx-click="moderate"
                phx-value-action="hide"
                class="btn btn-sm btn-warning"
              >
                Hide
              </button>
              <button
                :if={
                  @package.status == :hidden and
                    Permissions.can?(@current_admin, :unhide_package)
                }
                phx-click="moderate"
                phx-value-action="unhide"
                class="btn btn-sm btn-success"
              >
                Unhide
              </button>
              <button
                :if={
                  is_nil(@package.featured_at) and
                    Permissions.can?(@current_admin, :feature_package)
                }
                phx-click="moderate"
                phx-value-action="feature"
                class="btn btn-sm btn-primary"
              >
                Feature
              </button>
              <button
                :if={@package.featured_at && Permissions.can?(@current_admin, :feature_package)}
                phx-click="moderate"
                phx-value-action="unfeature"
                class="btn btn-sm btn-ghost"
              >
                Unfeature
              </button>
            </div>
          </div>

          <div class="grid gap-6 lg:grid-cols-2">
            <section class="rounded-box border border-base-300 bg-base-100">
              <header class="flex flex-wrap items-center justify-between gap-3 border-b border-base-300 p-4">
                <div class="flex items-center gap-2">
                  <h2 class="font-semibold">Source</h2>
                  <span :if={match?({:ok, _}, @source)} class="badge badge-ghost badge-sm">
                    {kind_label(elem(@source, 1).kind)}
                  </span>
                </div>

                <div :if={@selected_release} class="flex items-center gap-2">
                  <button
                    phx-click="navigate_release"
                    phx-value-direction="prev"
                    disabled={selected_index(@package, @selected_release) == 0}
                    aria-label="Older release"
                    class="btn btn-xs"
                  >
                    ←
                  </button>
                  <form phx-change="select_release" id="release-select">
                    <select
                      name="release"
                      aria-label="Release"
                      class="select select-bordered select-xs bg-base-100"
                    >
                      <option
                        :for={release <- Enum.reverse(@package.releases)}
                        value={release.id}
                        selected={release.id == @selected_release.id}
                      >
                        v{to_string(release.version)}{if release.yanked_at, do: " (yanked)"}
                      </option>
                    </select>
                  </form>
                  <button
                    phx-click="navigate_release"
                    phx-value-direction="next"
                    disabled={
                      selected_index(@package, @selected_release) == length(@package.releases) - 1
                    }
                    aria-label="Newer release"
                    class="btn btn-xs"
                  >
                    →
                  </button>
                </div>
              </header>

              <%= case @source do %>
                <% {:ok, source} -> %>
                  <div class="border-b border-base-300 px-4 py-2 text-xs text-base-content/60">
                    {source.filename}
                  </div>
                  <div class="max-h-[70vh] overflow-auto bg-base-200/40 p-4 font-mono text-xs leading-5">
                    <code class="source-code block whitespace-pre" phx-no-format>{render_source_lines(@source_lines)}</code>
                  </div>
                <% {:error, reason} -> %>
                  <div class="p-6 text-sm text-base-content/70">{error_label(reason)}</div>
              <% end %>
            </section>

            <section class="space-y-6">
              <div class="rounded-box border border-base-300 bg-base-100 p-4">
                <h2 class="font-semibold">Package</h2>
                <dl class="mt-4 grid grid-cols-[8rem_1fr] gap-y-3 text-sm">
                  <dt class="text-base-content/60">Owner</dt>
                  <dd>{@package.user.username}</dd>
                  <dt class="text-base-content/60">Status</dt>
                  <dd>{@package.status}</dd>
                  <dt class="text-base-content/60">Releases</dt>
                  <dd>{length(@package.releases)}</dd>
                  <dt class="text-base-content/60">Downloads</dt>
                  <dd>
                    {format_count(Enum.sum(for r <- @package.releases, do: r.download_count))}
                  </dd>
                  <dt class="text-base-content/60">Updated</dt>
                  <dd>{format_date(@package.updated_at)}</dd>
                  <dt :if={@selected_release} class="text-base-content/60">Selected</dt>
                  <dd :if={@selected_release}>
                    v{to_string(@selected_release.version)}
                    <span :if={@selected_release.yanked_at} class="badge badge-warning badge-xs ml-2">
                      Yanked
                    </span>
                  </dd>
                </dl>
              </div>

              <div class="rounded-box border border-base-300 bg-base-100 p-4">
                <h2 class="font-semibold">Summary</h2>
                <p class="mt-2 text-sm text-base-content/80">{@package.summary || "No summary"}</p>
                <div class="divider"></div>
                <h3 class="font-semibold">Description</h3>
                <p class="mt-2 text-sm text-base-content/80">
                  {@package.description || "No description"}
                </p>
              </div>

              <div
                :if={@package.moderation_note}
                class="rounded-box border border-warning/40 bg-warning/10 p-4"
              >
                <h2 class="font-semibold">Moderation note</h2>
                <p class="mt-2 whitespace-pre-line text-sm">{@package.moderation_note}</p>
              </div>
            </section>
          </div>
        </div>
      <% end %>
    </Layouts.admin>
    """
  end
end
