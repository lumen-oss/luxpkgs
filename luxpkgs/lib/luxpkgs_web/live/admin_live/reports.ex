defmodule LuxpkgsWeb.AdminLive.Reports do
  use LuxpkgsWeb, :live_view

  alias Luxpkgs.Admin.Permissions
  alias Luxpkgs.Moderation
  alias Luxpkgs.Packages
  alias LuxpkgsWeb.AdminAuth

  @impl true
  def mount(_params, _session, socket) do
    if Permissions.can?(socket.assigns.current_admin, :view_reports) do
      {:ok, assign(socket, :page_title, "Reports")}
    else
      {:ok,
       socket
       |> put_flash(:error, "You do not have permission to view reports.")
       |> redirect(to: ~p"/admin")}
    end
  end

  @impl true
  def handle_params(params, _url, socket) do
    filters = %{
      status: params["status"] || "open",
      reason: params["reason"] || "all",
      package: String.trim(params["package"] || ""),
      from: params["from"] || "",
      to: params["to"] || ""
    }

    {:noreply,
     socket
     |> assign(:filters, filters)
     |> assign(:params, params)
     |> assign(:reports, load_reports(filters))}
  end

  @impl true
  def handle_event("filter", params, socket) do
    clean =
      params
      |> Map.take(["status", "reason", "package", "from", "to"])
      |> Enum.reject(fn {key, value} ->
        value in [nil, ""] or (key == "status" and value == "open") or
          (key == "reason" and value == "all")
      end)
      |> Map.new()

    {:noreply, push_patch(socket, to: ~p"/admin/reports?#{clean}")}
  end

  def handle_event("hide_package", %{"id" => id}, socket) do
    with %{status: :open, package: package} <- Moderation.get_report(id),
         true <- Permissions.can?(socket.assigns.current_admin, :hide_package),
         true <- package.status == :active do
      case Packages.hide_package(socket.assigns.current_admin, package) do
        {:ok, _package} ->
          refresh(socket, :info, "Package hidden. The report remains open.")

        {:error, :insufficient_permissions} ->
          refresh(socket, :error, "You do not have permission to do that.")

        {:error, _reason} ->
          refresh(socket, :error, "Could not hide the package.")
      end
    else
      nil -> refresh(socket, :error, "Report not found.")
      _ -> refresh(socket, :error, "Could not hide the package.")
    end
  end

  def handle_event("remove_package", %{"id" => id}, socket) do
    if AdminAuth.destructive_fresh?(socket) do
      with %{status: :open, package: package} <- Moderation.get_report(id),
           true <- Permissions.can?(socket.assigns.current_admin, :remove_package),
           true <- package.status in [:active, :hidden] do
        case Packages.remove_package(socket.assigns.current_admin, package) do
          {:ok, _package} ->
            refresh(socket, :info, "Package removed. The report remains open.")

          {:error, :insufficient_permissions} ->
            refresh(socket, :error, "You do not have permission to do that.")

          {:error, _reason} ->
            refresh(socket, :error, "Could not remove the package.")
        end
      else
        nil -> refresh(socket, :error, "Report not found.")
        _ -> refresh(socket, :error, "Could not remove the package.")
      end
    else
      {:noreply,
       socket
       |> put_flash(:error, "Verify your second factor before removing a package.")
       |> redirect(to: ~p"/admin/verify")}
    end
  end

  def handle_event("act", %{"report_id" => id, "action" => action} = params, socket) do
    report = Moderation.get_report(id)
    note = params["note"] || ""

    case act(action, socket.assigns.current_admin, report, note) do
      {:ok, _result} ->
        refresh(socket, :info, success_message(action))

      {:error, :note_required} ->
        refresh(socket, :error, "Add a note before taking this action.")

      {:error, :insufficient_permissions} ->
        refresh(socket, :error, "You do not have permission to do that.")

      {:error, :not_open} ->
        refresh(socket, :error, "This report is already closed.")

      {:error, %Ecto.Changeset{}} ->
        refresh(socket, :error, "Could not update the report.")

      {:error, _reason} ->
        refresh(socket, :error, "Could not update the report.")
    end
  end

  defp act("resolve", admin, report, note), do: Moderation.resolve_report(admin, report, note)
  defp act("dismiss", admin, report, note), do: Moderation.dismiss_report(admin, report, note)
  defp act("warn", admin, report, note), do: Moderation.warn_report(admin, report, note)
  defp act(_action, _admin, _report, _note), do: {:error, :invalid_action}

  defp success_message("resolve"), do: "Report resolved."
  defp success_message("dismiss"), do: "Report dismissed."
  defp success_message("warn"), do: "Warning added to the package moderation note."
  defp success_message(_action), do: "Report updated."

  defp refresh(socket, level, message) do
    {:noreply,
     socket
     |> put_flash(level, message)
     |> assign(:reports, load_reports(socket.assigns.filters))}
  end

  defp load_reports(filters) do
    Moderation.list_reports(
      status: filters.status,
      reason: filters.reason,
      package: filters.package,
      from: parse_date(filters.from),
      to: parse_date(filters.to)
    )
  end

  defp parse_date(""), do: nil

  defp parse_date(value) when is_binary(value) do
    case Date.from_iso8601(value) do
      {:ok, date} -> date
      _ -> nil
    end
  end

  defp parse_date(_value), do: nil

  defp filtered?(filters) do
    filters.status != "open" or filters.reason != "all" or filters.package != "" or
      filters.from != "" or filters.to != ""
  end

  defp reporter_name(%{reporter: %{username: username}}), do: username
  defp reporter_name(_report), do: "Deleted user"

  defp reason_label(reason), do: reason |> to_string() |> String.capitalize()

  defp status_badge(:open), do: "badge badge-warning"
  defp status_badge(:resolved), do: "badge badge-success"
  defp status_badge(:dismissed), do: "badge badge-ghost"

  defp format_age(nil), do: "unknown"

  defp format_age(datetime) do
    seconds = max(NaiveDateTime.diff(NaiveDateTime.utc_now(), datetime), 0)

    cond do
      seconds < 60 -> "just now"
      seconds < 3_600 -> "#{div(seconds, 60)}m ago"
      seconds < 86_400 -> "#{div(seconds, 3_600)}h ago"
      true -> "#{div(seconds, 86_400)}d ago"
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin
      flash={@flash}
      current_scope={@current_scope}
      current_admin={@current_admin}
      active={:reports}
    >
      <div class="space-y-6">
        <div>
          <h1 class="text-2xl font-bold">Reports</h1>
          <p class="text-base-content/70">
            Review package reports. Oldest open reports appear first.
          </p>
        </div>

        <.form
          for={%{}}
          id="admin-reports-filters"
          phx-change="filter"
          class="grid gap-3 md:grid-cols-2 xl:grid-cols-[1fr_10rem_10rem_9rem_9rem_auto]"
        >
          <input
            type="search"
            name="package"
            value={@filters.package}
            placeholder="Filter by package"
            aria-label="Filter by package"
            class="input input-bordered w-full bg-base-100"
          />
          <select
            name="status"
            aria-label="Filter by status"
            class="select select-bordered w-full bg-base-100"
          >
            <option value="all" selected={@filters.status == "all"}>All statuses</option>
            <option value="open" selected={@filters.status == "open"}>Open</option>
            <option value="resolved" selected={@filters.status == "resolved"}>Resolved</option>
            <option value="dismissed" selected={@filters.status == "dismissed"}>Dismissed</option>
          </select>
          <select
            name="reason"
            aria-label="Filter by reason"
            class="select select-bordered w-full bg-base-100"
          >
            <option value="all" selected={@filters.reason == "all"}>All reasons</option>
            <option value="malicious" selected={@filters.reason == "malicious"}>Malicious</option>
            <option value="spam" selected={@filters.reason == "spam"}>Spam</option>
            <option value="copyright" selected={@filters.reason == "copyright"}>Copyright</option>
            <option value="broken" selected={@filters.reason == "broken"}>Broken</option>
            <option value="other" selected={@filters.reason == "other"}>Other</option>
          </select>
          <input
            type="date"
            name="from"
            value={@filters.from}
            aria-label="Reports from date"
            class="input input-bordered w-full bg-base-100"
          />
          <input
            type="date"
            name="to"
            value={@filters.to}
            aria-label="Reports to date"
            class="input input-bordered w-full bg-base-100"
          />
          <.link :if={filtered?(@filters)} patch={~p"/admin/reports"} class="btn btn-ghost">
            <.icon name={:x} type={:outline} class="size-4" /> Clear
          </.link>
        </.form>

        <p
          :if={@reports == []}
          class="rounded-box border border-base-300 bg-base-100 p-8 text-center text-sm text-base-content/70"
        >
          No reports match these filters.
        </p>

        <div :if={@reports != []} class="space-y-4">
          <article
            :for={report <- @reports}
            id={"report-#{report.id}"}
            class="rounded-box border border-base-300 bg-base-100 p-4 lg:p-6"
          >
            <div class="flex flex-wrap items-start justify-between gap-3">
              <div>
                <div class="flex flex-wrap items-center gap-2">
                  <.link
                    navigate={~p"/admin/packages/#{report.package_id}"}
                    class="font-semibold link link-hover"
                  >
                    {report.package.name}
                  </.link>
                  <span class={status_badge(report.status)}>{report.status}</span>
                </div>
                <p class="mt-1 text-sm text-base-content/70">
                  {reason_label(report.reason)} reported by {reporter_name(report)} · {format_age(
                    report.inserted_at
                  )}
                </p>
              </div>
              <span class="text-xs text-base-content/60">Report #{report.id}</span>
            </div>

            <p :if={report.details} class="mt-3 line-clamp-3 text-sm text-base-content/80">
              {report.details}
            </p>

            <p
              :if={report.package.moderation_note}
              class="mt-3 rounded-box border border-warning/40 bg-warning/10 p-3 text-sm"
            >
              <span class="font-medium">Package moderation note:</span>
              <br/>
              {report.package.moderation_note}
            </p>

            <p
              :if={report.resolution_note}
              class="mt-3 rounded-box border border-base-300 bg-base-200 p-3 text-sm"
            >
              <span class="font-medium">Resolution:</span> {report.resolution_note}
            </p>

            <%= if report.status == :open do %>
              <div class="mt-4 flex flex-wrap gap-2">
                <button
                  :if={
                    Permissions.can?(@current_admin, :hide_package) and
                      report.package.status == :active
                  }
                  phx-click="hide_package"
                  phx-value-id={report.id}
                  class="btn btn-sm btn-warning"
                >
                  <.icon name={:eye_off} type={:outline} class="size-4" /> Hide package
                </button>
                <button
                  :if={
                    Permissions.can?(@current_admin, :remove_package) and
                      report.package.status in [:active, :hidden]
                  }
                  phx-click="remove_package"
                  phx-value-id={report.id}
                  class="btn btn-sm btn-error"
                >
                  <.icon name={:trash} type={:outline} class="size-4" /> Remove package
                </button>
              </div>

              <form phx-submit="act" class="mt-4 space-y-3">
                <input type="hidden" name="report_id" value={report.id} />
                <textarea
                  name="note"
                  rows="2"
                  required
                  maxlength="1000"
                  placeholder="Add a note for resolve, dismiss or warn"
                  aria-label="Report action note"
                  class="textarea textarea-bordered w-full bg-base-100"
                ></textarea>
                <div class="flex flex-wrap gap-2">
                  <button type="submit" name="action" value="resolve" class="btn btn-sm btn-success">
                    Resolve
                  </button>
                  <button type="submit" name="action" value="dismiss" class="btn btn-sm">
                    Dismiss
                  </button>
                  <button type="submit" name="action" value="warn" class="btn btn-sm btn-ghost">
                    Warn
                  </button>
                </div>
              </form>
            <% end %>
          </article>
        </div>
      </div>
    </Layouts.admin>
    """
  end
end
