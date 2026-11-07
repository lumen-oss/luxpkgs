defmodule Luxpkgs.Audit do
  import Ecto.Query, warn: false

  alias Luxpkgs.Audit.Event
  alias Luxpkgs.Repo

  @topic "admin:audit"
  @default_limit 100
  # shortcut: newest-first list capped at 500 events, add keyset pagination when the log outgrows it.
  @max_limit 500

  def changeset(attrs) when is_map(attrs), do: Event.changeset(%Event{}, attrs)

  def record(attrs) when is_map(attrs) do
    %Event{}
    |> Event.changeset(attrs)
    |> Repo.insert()
    |> case do
      {:ok, event} ->
        broadcast(event)
        {:ok, event}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  def broadcast(%Event{} = event) do
    Phoenix.PubSub.broadcast(Luxpkgs.PubSub, @topic, {:audit_event, event})
    :ok
  end

  def subscribe do
    Phoenix.PubSub.subscribe(Luxpkgs.PubSub, @topic)
  end

  def topic, do: @topic

  def list_events, do: list_events([])

  def list_events(limit) when is_integer(limit), do: list_events(limit: limit)

  def list_events(opts) when is_list(opts) do
    opts
    |> Enum.into(%{})
    |> events_query()
    |> Repo.all()
  end

  def list_actors do
    Repo.all(
      from event in Event,
        where: not is_nil(event.actor_label),
        distinct: event.actor_label,
        order_by: [asc: event.actor_label],
        select: event.actor_label,
        limit: 100
    )
  end

  defp events_query(opts) do
    from(event in Event,
      order_by: [desc: event.inserted_at, desc: event.id],
      limit: ^limit(opts),
      preload: [:actor_admin]
    )
    |> filter_type(opts[:type])
    |> filter_action(opts[:action])
    |> filter_actor(opts[:actor])
    |> filter_target_type(opts[:target_type])
    |> filter_search(opts[:q])
    |> filter_from(opts[:from])
    |> filter_to(opts[:to])
  end

  defp filter_type(query, type) when type in [nil, "", "all"], do: query

  defp filter_type(query, type) when is_atom(type) do
    if type in Event.types() do
      where(query, [event], event.type == ^type)
    else
      query
    end
  end

  defp filter_type(query, type) when is_binary(type) do
    case Enum.find(Event.types(), &(Atom.to_string(&1) == type)) do
      nil -> query
      event_type -> where(query, [event], event.type == ^event_type)
    end
  end

  defp filter_type(query, _type), do: query

  defp filter_action(query, action) when action in [nil, "", "all"], do: query

  defp filter_action(query, action) when is_binary(action) do
    where(query, [event], event.action == ^action)
  end

  defp filter_action(query, _action), do: query

  defp filter_actor(query, actor) when is_binary(actor) do
    case String.trim(actor) do
      "" ->
        query

      actor ->
        where(query, [event], ilike(event.actor_label, ^"%#{escape_like(actor)}%"))
    end
  end

  defp filter_actor(query, _actor), do: query

  defp filter_target_type(query, target_type) when target_type in [nil, "", "all"], do: query

  defp filter_target_type(query, target_type) when is_binary(target_type) do
    where(query, [event], event.target_type == ^target_type)
  end

  defp filter_target_type(query, _target_type), do: query

  defp filter_search(query, term) when is_binary(term) do
    case String.trim(term) do
      "" ->
        query

      term ->
        pattern = "%#{escape_like(term)}%"

        where(
          query,
          [event],
          ilike(event.actor_label, ^pattern) or
            ilike(event.action, ^pattern) or
            ilike(event.target_label, ^pattern) or
            ilike(event.target_type, ^pattern) or
            fragment("?::text ILIKE ?", event.metadata, ^pattern)
        )
    end
  end

  defp filter_search(query, _term), do: query

  defp filter_from(query, %Date{} = date) do
    where(query, [event], event.inserted_at >= ^start_of_day(date))
  end

  defp filter_from(query, _from), do: query

  defp filter_to(query, %Date{} = date) do
    where(query, [event], event.inserted_at < ^start_of_day(Date.add(date, 1)))
  end

  defp filter_to(query, _to), do: query

  defp limit(opts) do
    opts
    |> Map.get(:limit, @default_limit)
    |> normalize_limit()
  end

  defp normalize_limit(value) when is_integer(value), do: value |> max(1) |> min(@max_limit)

  defp normalize_limit(value) when is_binary(value) do
    case Integer.parse(value) do
      {limit, ""} -> normalize_limit(limit)
      _ -> @default_limit
    end
  end

  defp normalize_limit(_value), do: @default_limit

  defp start_of_day(date), do: DateTime.new!(date, ~T[00:00:00], "Etc/UTC")

  defp escape_like(value) do
    value
    |> String.replace("\\", "\\\\")
    |> String.replace("%", "\\%")
    |> String.replace("_", "\\_")
  end
end
