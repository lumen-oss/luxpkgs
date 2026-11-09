defmodule LuxpkgsWeb.AdminLive.Audit do
  use LuxpkgsWeb, :live_view

  alias Luxpkgs.Admin.Permissions
  alias Luxpkgs.Audit
  alias Luxpkgs.Audit.Catalog
  alias Luxpkgs.Audit.Event

  @default_limit 100
  @max_limit 500

  @impl true
  def mount(_params, _session, socket) do
    if Permissions.can?(socket.assigns.current_admin, :view_audit) do
      if connected?(socket), do: Audit.subscribe()

      {:ok,
       assign(socket,
         page_title: "Audit log",
         actors: Audit.list_actors(),
         target_types: ~w(admin package release report user),
         ranges: [{"24h", 1}, {"7d", 7}, {"30d", 30}, {"90d", 90}, {"All", nil}]
       )}
    else
      {:ok,
       socket
       |> put_flash(:error, "You do not have permission to view the audit log.")
       |> redirect(to: ~p"/admin")}
    end
  end

  @impl true
  def handle_params(params, _url, socket) do
    filters = filters(params)
    limit = limit(params["limit"])

    {:noreply,
     socket
     |> assign(:filters, filters)
     |> assign(:limit, limit)
     |> assign_events()}
  end

  @impl true
  def handle_event("filter", params, socket) do
    clean =
      params
      |> Map.take(~w(q type action actor target_type from to))
      |> Enum.reject(fn {key, value} ->
        value in [nil, ""] or
          (key == "type" and value == "all") or
          (key == "action" and value == "all") or
          (key == "target_type" and value == "all")
      end)
      |> Map.new()

    {:noreply, push_patch(socket, to: ~p"/admin/audit?#{clean}")}
  end

  @impl true
  def handle_info({:audit_event, _event}, socket) do
    {:noreply, assign_events(socket)}
  end

  defp filters(params) do
    %{
      q: trim(params["q"]),
      type: valid_type(params["type"]),
      action: valid_action(params["action"]),
      actor: trim(params["actor"]),
      target_type: valid_target_type(params["target_type"]),
      from: params["from"] || "",
      to: params["to"] || ""
    }
  end

  defp trim(value) when is_binary(value), do: String.trim(value)
  defp trim(_value), do: ""

  defp valid_type(nil), do: "all"
  defp valid_type("all"), do: "all"

  defp valid_type(value) do
    if value in Enum.map(Event.types(), &Atom.to_string/1), do: value, else: "all"
  end

  defp valid_action(nil), do: "all"
  defp valid_action("all"), do: "all"

  defp valid_action(value) do
    if value in Catalog.action_names(), do: value, else: "all"
  end

  defp valid_target_type(nil), do: "all"
  defp valid_target_type("all"), do: "all"

  defp valid_target_type(value) do
    if value in ~w(admin package release report user), do: value, else: "all"
  end

  defp limit(nil), do: @default_limit

  defp limit(value) when is_binary(value) do
    case Integer.parse(value) do
      {limit, ""} -> limit |> max(1) |> min(@max_limit)
      _ -> @default_limit
    end
  end

  defp limit(_value), do: @default_limit

  defp assign_events(socket) do
    filters = socket.assigns.filters
    limit = socket.assigns.limit

    events =
      Audit.list_events(
        q: filters.q,
        type: filters.type,
        action: filters.action,
        actor: filters.actor,
        target_type: filters.target_type,
        from: parse_date(filters.from),
        to: parse_date(filters.to),
        limit: limit + 1
      )

    has_more = length(events) > limit
    events = Enum.take(events, limit)

    groups =
      events
      |> Enum.group_by(&DateTime.to_date(&1.inserted_at))
      |> Enum.sort_by(fn {date, _events} -> Date.to_iso8601(date) end, :desc)

    assign(socket, events: events, groups: groups, has_more: has_more)
  end

  defp parse_date(""), do: nil

  defp parse_date(value) when is_binary(value) do
    case Date.from_iso8601(value) do
      {:ok, date} -> date
      _ -> nil
    end
  end

  defp parse_date(_value), do: nil

  defp query_params(filters) do
    %{
      "q" => filters.q,
      "type" => filters.type,
      "action" => filters.action,
      "actor" => filters.actor,
      "target_type" => filters.target_type,
      "from" => filters.from,
      "to" => filters.to
    }
    |> Enum.reject(fn {key, value} ->
      value in [nil, ""] or
        (key == "type" and value == "all") or
        (key == "action" and value == "all") or
        (key == "target_type" and value == "all")
    end)
    |> Map.new()
  end

  defp range_path(filters, nil) do
    ~p"/admin/audit?#{Map.drop(query_params(filters), ["from", "to"])}"
  end

  defp range_path(filters, days) do
    params =
      filters
      |> Map.put(:from, range_from(days))
      |> Map.put(:to, "")
      |> query_params()

    ~p"/admin/audit?#{params}"
  end

  defp range_from(days), do: Date.utc_today() |> Date.add(-days) |> Date.to_iso8601()

  defp active_range?(filters, nil), do: filters.from == "" and filters.to == ""
  defp active_range?(filters, days), do: filters.from == range_from(days) and filters.to == ""

  defp more_path(filters, limit) do
    params = filters |> query_params() |> Map.put("limit", limit)
    ~p"/admin/audit?#{params}"
  end

  defp filtered?(filters) do
    filters.q != "" or filters.type != "all" or filters.action != "all" or
      filters.actor != "" or filters.target_type != "all" or filters.from != "" or
      filters.to != ""
  end

  defp actor_params(filters, actor) do
    params = filters |> Map.put(:actor, actor) |> query_params()
    ~p"/admin/audit?#{params}"
  end

  defp format_age(nil), do: "unknown"

  defp format_age(datetime) do
    seconds = max(DateTime.diff(DateTime.utc_now(), datetime, :second), 0)

    cond do
      seconds < 60 -> "just now"
      seconds < 3_600 -> "#{div(seconds, 60)}m ago"
      seconds < 86_400 -> "#{div(seconds, 3_600)}h ago"
      seconds < 604_800 -> "#{div(seconds, 86_400)}d ago"
      true -> Calendar.strftime(datetime, "%b %d")
    end
  end

  defp format_datetime(nil), do: "-"
  defp format_datetime(datetime), do: Calendar.strftime(datetime, "%b %d, %Y at %H:%M:%S UTC")

  defp day_label(date) do
    today = Date.utc_today()

    cond do
      date == today -> "Today"
      date == Date.add(today, -1) -> "Yesterday"
      true -> Calendar.strftime(date, "%A, %B %d, %Y")
    end
  end

  defp type_name(:package), do: "Package"
  defp type_name(:report), do: "Report"
  defp type_name(:user), do: "User"
  defp type_name(:auth), do: "Auth"
  defp type_name(:system), do: "System"

  defp type_label(type), do: type |> type_name() |> String.upcase()

  defp type_badge(:package), do: "badge badge-info badge-sm font-medium"
  defp type_badge(:report), do: "badge badge-warning badge-sm font-medium"
  defp type_badge(:user), do: "badge badge-error badge-sm font-medium"
  defp type_badge(:auth), do: "badge badge-secondary badge-sm font-medium"
  defp type_badge(:system), do: "badge badge-ghost badge-sm font-medium"

  defp type_icon(:package), do: :package
  defp type_icon(:report), do: :flag
  defp type_icon(:user), do: :user
  defp type_icon(:auth), do: :shield_check
  defp type_icon(:system), do: :settings

  defp marker_class(:package), do: "border-info/80 bg-info/30 text-info"
  defp marker_class(:report), do: "border-warning/80 bg-warning/30 text-warning"
  defp marker_class(:user), do: "border-error/80 bg-error/30 text-error"
  defp marker_class(:auth), do: "border-secondary/80 bg-secondary/30 text-secondary"
  defp marker_class(:system), do: "border-base-300 bg-base-200 text-base-content/70"

  defp target_label(event) do
    if event.target_label in [nil, ""] or event.target_label == event.actor_label do
      nil
    else
      event.target_label
    end
  end

  defp target_path(%{target_type: "package", target_id: id}) when is_integer(id) do
    ~p"/admin/packages/#{id}"
  end

  defp target_path(%{metadata: metadata}) when is_map(metadata) do
    case metadata["package_id"] do
      id when is_integer(id) -> ~p"/admin/packages/#{id}"
      _ -> nil
    end
  end

  defp target_path(_event), do: nil

  defp summary_chips(event) do
    metadata = event.metadata || %{}

    []
    |> maybe_chip(status_chip(metadata))
    |> maybe_chip(metadata["note"] && "note: #{metadata["note"]}")
    |> maybe_chip(metadata["reason"] && "reason: #{metadata["reason"]}")
    |> maybe_chip(metadata["version"] && "version #{metadata["version"]}")
    |> maybe_chip(metadata["provider"] && "provider: #{metadata["provider"]}")
    |> Enum.take(3)
  end

  defp status_chip(%{"from" => from, "to" => to}), do: "#{from} -> #{to}"
  defp status_chip(_metadata), do: nil

  defp maybe_chip(chips, nil), do: chips
  defp maybe_chip(chips, ""), do: chips
  defp maybe_chip(chips, chip), do: chips ++ [chip]

  defp metadata_empty?(metadata), do: metadata in [nil, %{}]

  defp metadata_entries(metadata) when is_map(metadata) do
    metadata
    |> Enum.sort_by(fn {key, _value} -> to_string(key) end)
    |> Enum.map(fn {key, value} -> {to_string(key), value} end)
  end

  defp metadata_entries(_metadata), do: []

  defp max_limit, do: @max_limit

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin
      flash={@flash}
      current_scope={@current_scope}
      current_admin={@current_admin}
      active={:audit}
    >
      <div class="space-y-6">
        <div class="flex flex-wrap items-start justify-between gap-3">
          <div>
            <h1 class="text-2xl font-bold">Audit log</h1>
            <p class="text-base-content/70">
              Every admin and high-impact action, newest first.
            </p>
          </div>
          <div class="flex flex-wrap items-center gap-3 text-sm text-base-content/70">
            <span class="inline-flex items-center gap-1.5 rounded-full border border-success/30 bg-success/10 px-2.5 py-1 text-xs font-medium text-success">
              <span class="size-1.5 animate-pulse rounded-full bg-success"></span> Live
            </span>
            <span>{length(@events)} loaded</span>
          </div>
        </div>

        <div class="space-y-3">
          <div class="flex flex-wrap items-center gap-2">
            <span class="text-xs font-medium uppercase tracking-wide text-base-content/50">
              Range
            </span>
            <.link
              :for={{label, days} <- @ranges}
              patch={range_path(@filters, days)}
              class={[
                "btn btn-xs",
                if(active_range?(@filters, days), do: "btn-primary", else: "btn-ghost")
              ]}
            >
              {label}
            </.link>
          </div>

          <.form for={%{}} id="admin-audit-filters" phx-change="filter" class="space-y-3">
            <div class="grid gap-3 md:grid-cols-2 xl:grid-cols-[minmax(0,2fr)_10rem_14rem_auto]">
              <input
                type="search"
                name="q"
                value={@filters.q}
                placeholder="Search actor, action, target, note..."
                aria-label="Search audit events"
                phx-debounce="300"
                class="input input-bordered w-full bg-base-100"
              />
              <select
                name="type"
                aria-label="Filter by type"
                class="select select-bordered w-full bg-base-100"
              >
                <option value="all" selected={@filters.type == "all"}>All types</option>
                <option
                  :for={type <- Event.types()}
                  value={type}
                  selected={@filters.type == to_string(type)}
                >
                  {type_name(type)}
                </option>
              </select>
              <select
                name="action"
                aria-label="Filter by action"
                class="select select-bordered w-full bg-base-100"
              >
                <option value="all" selected={@filters.action == "all"}>All actions</option>
                <optgroup :for={group <- Catalog.groups()} label={group.label}>
                  <option
                    :for={action <- group.actions}
                    value={action.action}
                    selected={@filters.action == action.action}
                  >
                    {action.label}
                  </option>
                </optgroup>
              </select>
              <.link
                :if={filtered?(@filters)}
                patch={~p"/admin/audit"}
                class="btn btn-ghost"
              >
                <.icon name={:x} type={:outline} class="size-4" /> Clear
              </.link>
            </div>

            <div class="grid gap-3 md:grid-cols-2 xl:grid-cols-[1fr_10rem_9rem_9rem]">
              <input
                type="text"
                name="actor"
                value={@filters.actor}
                placeholder="Filter by actor"
                aria-label="Filter by actor"
                list="audit-actors"
                phx-debounce="300"
                class="input input-bordered w-full bg-base-100"
              />
              <datalist id="audit-actors">
                <option :for={actor <- @actors} value={actor}>{actor}</option>
              </datalist>
              <select
                name="target_type"
                aria-label="Filter by target type"
                class="select select-bordered w-full bg-base-100"
              >
                <option value="all" selected={@filters.target_type == "all"}>All targets</option>
                <option
                  :for={target_type <- @target_types}
                  value={target_type}
                  selected={@filters.target_type == target_type}
                >
                  {String.capitalize(target_type)}
                </option>
              </select>
              <input
                type="date"
                name="from"
                value={@filters.from}
                aria-label="From date"
                class="input input-bordered w-full bg-base-100"
              />
              <input
                type="date"
                name="to"
                value={@filters.to}
                aria-label="To date"
                class="input input-bordered w-full bg-base-100"
              />
            </div>
          </.form>
        </div>

        <div
          :if={@events == []}
          class="rounded-box border border-dashed border-base-300 bg-base-100 p-8 text-center"
        >
          <div class="mx-auto flex size-10 items-center justify-center rounded-full bg-base-200 text-base-content/50">
            <.icon name={:file_text} type={:outline} class="size-5" />
          </div>
          <h2 class="mt-3 text-lg font-semibold">
            {if filtered?(@filters),
              do: "No audit events match these filters.",
              else: "No audit events recorded yet."}
          </h2>
          <p :if={filtered?(@filters)} class="mt-1 text-sm text-base-content/70">
            Try a wider date range or clear a filter.
          </p>
          <.link :if={filtered?(@filters)} patch={~p"/admin/audit"} class="btn btn-sm mt-4">
            Clear filters
          </.link>
        </div>

        <div :if={@events != []} class="space-y-6">
          <section :for={{date, events} <- @groups} class="space-y-3">
            <h2 class="text-sm font-medium text-base-content/70">{day_label(date)}</h2>
            <div class="relative">
              <span
                class="pointer-events-none absolute bottom-0 left-[0.875rem] top-0 w-px bg-base-300"
                aria-hidden="true"
              ></span>
              <ol class="space-y-4 pl-10 sm:pl-12">
                <li :for={event <- events} class="relative">
                  <span class={[
                    "absolute -left-10 top-4 z-10 flex size-7.5 items-center justify-center rounded-full border bg-base-100 sm:-left-12",
                    marker_class(event.type)
                  ]}>
                    <.icon name={type_icon(event.type)} type={:outline} class="size-4" />
                  </span>
                  <article class="rounded-box border border-base-300 bg-base-100 p-4">
                    <div class="flex flex-wrap items-start justify-between gap-x-4 gap-y-2">
                      <div class="flex min-w-0 flex-wrap items-center gap-x-2 gap-y-1">
                        <span class={type_badge(event.type)}>{type_label(event.type)}</span>
                        <.link
                          :if={event.actor_label}
                          patch={actor_params(@filters, event.actor_label)}
                          class="link link-hover text-sm font-medium"
                        >
                          {event.actor_label}
                        </.link>
                        <span :if={is_nil(event.actor_label)} class="text-sm font-medium">
                          System
                        </span>
                        <span class="text-sm text-base-content/70">
                          {Catalog.label(event.action)}
                        </span>
                        <.link
                          :if={target_label(event) && target_path(event)}
                          navigate={target_path(event)}
                          class="link link-hover text-sm font-medium"
                        >
                          {target_label(event)}
                        </.link>
                        <span
                          :if={target_label(event) && is_nil(target_path(event))}
                          class="text-sm font-medium"
                        >
                          {target_label(event)}
                        </span>
                      </div>
                      <time
                        class="text-xs text-base-content/70"
                        datetime={DateTime.to_iso8601(event.inserted_at)}
                        title={format_datetime(event.inserted_at)}
                      >
                        {format_age(event.inserted_at)}
                      </time>
                    </div>

                    <p class="mt-1 text-xs text-base-content/50">
                      {format_datetime(event.inserted_at)} · event #{event.id}
                    </p>

                    <div :if={summary_chips(event) != []} class="mt-2 flex flex-wrap gap-1.5">
                      <span
                        :for={chip <- summary_chips(event)}
                        class="badge badge-ghost badge-sm max-w-full truncate"
                        title={chip}
                      >
                        {chip}
                      </span>
                    </div>

                    <details class="group mt-3 rounded-box border border-base-300 bg-base-200/40">
                      <summary class="flex cursor-pointer list-none items-center gap-2 px-3 py-2 text-sm font-medium text-base-content/70">
                        <.icon
                          name={:chevron_right}
                          type={:outline}
                          class="size-4 transition-transform group-open:rotate-90"
                        /> Details
                      </summary>
                      <div class="border-t border-base-300 px-3 py-3">
                        <p
                          :if={metadata_empty?(event.metadata)}
                          class="text-sm text-base-content/70"
                        >
                          No metadata.
                        </p>
                        <dl
                          :if={!metadata_empty?(event.metadata)}
                          class="grid gap-x-4 gap-y-2 text-sm sm:grid-cols-[10rem_minmax(0,1fr)]"
                        >
                          <div
                            :for={{key, value} <- metadata_entries(event.metadata)}
                            class="contents"
                          >
                            <dt class="font-medium text-base-content/70">{key}</dt>
                            <dd class="min-w-0">
                              <p
                                :if={is_binary(value)}
                                class="whitespace-pre-line break-words"
                                phx-no-format
                              >{value}</p>
                              <pre
                                :if={!is_binary(value)}
                                class="overflow-x-auto rounded-box bg-base-300/50 p-2 text-xs"
                                phx-no-format
                              >{inspect(value, pretty: true)}</pre>
                            </dd>
                          </div>
                        </dl>
                      </div>
                    </details>
                  </article>
                </li>
              </ol>
            </div>
          </section>
        </div>

        <div :if={@has_more and @limit < max_limit()} class="flex justify-center pt-2">
          <.link patch={more_path(@filters, min(@limit + 100, max_limit()))} class="btn btn-sm">
            Load older events
          </.link>
        </div>
        <p
          :if={@has_more and @limit >= max_limit()}
          class="text-center text-sm text-base-content/70"
        >
          Showing the newest {@limit} events. Narrow the filters or date range to see older events.
        </p>
      </div>
    </Layouts.admin>
    """
  end
end
