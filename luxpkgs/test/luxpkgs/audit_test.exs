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
  end
end
