defmodule Luxpkgs.Audit do
  import Ecto.Query, warn: false

  alias Luxpkgs.Audit.Event
  alias Luxpkgs.Repo

  @topic "admin:audit"

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

  def list_events(limit \\ 50) when is_integer(limit) and limit > 0 do
    Repo.all(
      from event in Event,
        order_by: [desc: event.inserted_at, desc: event.id],
        limit: ^limit,
        preload: [:actor_admin]
    )
  end
end
