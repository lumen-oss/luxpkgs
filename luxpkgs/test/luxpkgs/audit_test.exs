defmodule Luxpkgs.AuditTest do
  use Luxpkgs.DataCase, async: false

  alias Luxpkgs.Audit
  alias Luxpkgs.Audit.Event

  describe "record/1" do
    test "inserts a compact event and broadcasts it" do
      Audit.subscribe()

      attrs = %{
        type: :system,
        action: "system.test",
        actor_label: "system",
        metadata: %{"ok" => true}
      }

      assert {:ok, %Event{} = event} = Audit.record(attrs)
      assert event.type == :system
      assert event.action == "system.test"
      assert event.actor_admin_id == nil
      assert event.actor_label == "system"
      assert event.metadata == %{"ok" => true}
      assert event.inserted_at

      event_id = event.id
      assert_receive {:audit_event, %Event{id: ^event_id}}
    end

    test "requires type, action, and actor label" do
      assert {:error, changeset} = Audit.record(%{})

      assert %{
               type: ["can't be blank"],
               action: ["can't be blank"],
               actor_label: ["can't be blank"]
             } = errors_on(changeset)
    end

    test "rejects unknown event types" do
      assert {:error, changeset} =
               Audit.record(%{type: :bogus, action: "system.test", actor_label: "system"})

      assert %{type: ["is invalid"]} = errors_on(changeset)
    end
  end

  describe "list_events/1" do
    test "returns the newest events first" do
      assert {:ok, first} =
               Audit.record(%{type: :system, action: "system.first", actor_label: "system"})

      assert {:ok, second} =
               Audit.record(%{type: :system, action: "system.second", actor_label: "system"})

      first_id = first.id
      second_id = second.id

      assert [%Event{id: ^second_id}, %Event{id: ^first_id}] = Audit.list_events()
    end

    test "filters by type, action, actor, and target type" do
      package_event =
        event!(%{
          type: :package,
          action: "package.hidden",
          actor_label: "admin",
          target_type: "package",
          target_id: 1,
          target_label: "alpha"
        })

      report_event =
        event!(%{
          type: :report,
          action: "report.resolved",
          actor_label: "moderator",
          target_type: "report",
          target_id: 2,
          target_label: "beta"
        })

      user_event =
        event!(%{
          type: :user,
          action: "user.registered",
          actor_label: "alice",
          target_type: "user",
          target_id: 3,
          target_label: "alice"
        })

      assert ids(Audit.list_events(type: "report")) == [report_event.id]
      assert ids(Audit.list_events(type: :user)) == [user_event.id]
      assert ids(Audit.list_events(action: "package.hidden")) == [package_event.id]
      assert ids(Audit.list_events(actor: "mod")) == [report_event.id]
      assert ids(Audit.list_events(target_type: "package")) == [package_event.id]
    end

    test "searches actor, action, target, and metadata" do
      package_event =
        event!(%{
          type: :package,
          action: "package.hidden",
          actor_label: "admin",
          target_type: "package",
          target_id: 1,
          target_label: "alpha",
          metadata: %{"note" => "removed malware"}
        })

      report_event =
        event!(%{
          type: :report,
          action: "report.resolved",
          actor_label: "moderator",
          target_type: "report",
          target_id: 2,
          target_label: "beta",
          metadata: %{"note" => "handled cleanly"}
        })

      assert ids(Audit.list_events(q: "malware")) == [package_event.id]
      assert ids(Audit.list_events(q: "beta")) == [report_event.id]
      assert ids(Audit.list_events(q: "resolv")) == [report_event.id]
      assert ids(Audit.list_events(q: "moder")) == [report_event.id]
    end

    test "filters by an inclusive date range" do
      january =
        event!(%{type: :system, action: "system.january", actor_label: "system"})
        |> at!(~U[2026-01-31 23:59:59.000000Z])

      february =
        event!(%{type: :system, action: "system.february", actor_label: "system"})
        |> at!(~U[2026-02-01 00:00:00.000000Z])

      assert ids(Audit.list_events(from: ~D[2026-02-01])) == [february.id]
      assert ids(Audit.list_events(to: ~D[2026-01-31])) == [january.id]

      assert ids(Audit.list_events(from: ~D[2026-01-31], to: ~D[2026-01-31])) ==
               [january.id]

      assert ids(Audit.list_events(from: ~D[2026-01-01], to: ~D[2026-02-01])) ==
               [february.id, january.id]
    end

    test "supports integer limits and clamps them" do
      event!(%{type: :system, action: "system.one", actor_label: "system"})
      event!(%{type: :system, action: "system.two", actor_label: "system"})

      assert length(Audit.list_events(1)) == 1
      assert length(Audit.list_events(limit: 1)) == 1
      assert length(Audit.list_events(limit: 0)) == 1
    end

    test "lists distinct actors in order" do
      event!(%{type: :system, action: "system.one", actor_label: "system"})
      event!(%{type: :system, action: "system.two", actor_label: "admin"})
      event!(%{type: :system, action: "system.three", actor_label: "admin"})

      assert Audit.list_actors() == ["admin", "system"]
    end
  end

  defp event!(attrs) do
    {:ok, event} = Audit.record(Map.merge(%{actor_label: "admin"}, attrs))
    event
  end

  defp at!(event, datetime) do
    event
    |> Ecto.Changeset.change(inserted_at: datetime)
    |> Luxpkgs.Repo.update!()
  end

  defp ids(events), do: Enum.map(events, & &1.id)
end
