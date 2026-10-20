defmodule Luxpkgs.AdminTest do
  use Luxpkgs.DataCase, async: true

  alias Luxpkgs.Accounts
  alias Luxpkgs.Admin
  alias Luxpkgs.Admin.Admin, as: AdminRecord
  alias Luxpkgs.Audit
  alias Luxpkgs.Repo

  import Luxpkgs.AccountsFixtures

  describe "grant_by_user_id/2" do
    test "grants the admin role" do
      user = user_fixture()

      assert {:ok, %AdminRecord{} = admin} = Admin.grant_by_user_id(user.id, :admin)
      assert admin.user_id == user.id
      assert admin.user.id == user.id
      assert admin.role == :admin
      assert admin.active
    end

    test "grants the moderator role" do
      user = user_fixture()

      assert {:ok, %AdminRecord{role: :moderator}} =
               Admin.grant_by_user_id(user.id, :moderator)
    end

    test "accepts role strings" do
      user = user_fixture()

      assert {:ok, %AdminRecord{role: :admin}} = Admin.grant_by_user_id(user.id, "admin")
    end

    test "rejects unknown users" do
      assert {:error, :user_not_found} = Admin.grant_by_user_id(999_999, :admin)
    end

    test "rejects the deleted user sentinel" do
      deleted = Accounts.deleted_user()

      assert {:error, :deleted_user} = Admin.grant_by_user_id(deleted.id, :admin)
    end

    test "rejects invalid user ids" do
      assert {:error, :invalid_user_id} = Admin.grant_by_user_id(0, :admin)
      assert {:error, :invalid_user_id} = Admin.grant_by_user_id(-1, :admin)
      assert {:error, :invalid_user_id} = Admin.grant_by_user_id("1", :admin)
    end

    test "rejects invalid roles" do
      user = user_fixture()

      assert {:error, :invalid_role} = Admin.grant_by_user_id(user.id, :owner)
      assert {:error, :invalid_role} = Admin.grant_by_user_id(user.id, "owner")
    end

    test "is idempotent when the admin already has the role" do
      user = user_fixture()

      assert {:ok, admin} = Admin.grant_by_user_id(user.id, :moderator)
      assert {:ok, %AdminRecord{id: same_id}} = Admin.grant_by_user_id(user.id, :moderator)
      assert same_id == admin.id
      assert Repo.aggregate(AdminRecord, :count, :id) == 1
      assert Repo.aggregate(Audit.Event, :count, :id) == 1
    end

    test "changes an existing role and audits the change" do
      user = user_fixture()

      assert {:ok, _admin} = Admin.grant_by_user_id(user.id, :moderator)
      assert {:ok, %AdminRecord{role: :admin}} = Admin.grant_by_user_id(user.id, :admin)

      event = Repo.get_by(Audit.Event, action: "admin.role_changed")
      assert event.type == :auth
      assert event.actor_admin_id == nil
      assert event.actor_label == "cli"
      assert event.target_type == "user"
      assert event.target_id == user.id
      assert event.target_label == user.username
      assert event.metadata == %{"from" => "moderator", "to" => "admin"}
    end

    test "reactivates a revoked admin and audits the grant" do
      user = user_fixture()

      assert {:ok, _admin} = Admin.grant_by_user_id(user.id, :moderator)
      assert {:ok, %AdminRecord{active: false}} = Admin.revoke_by_user_id(user.id)

      assert {:ok, %AdminRecord{active: true, role: :admin}} =
               Admin.grant_by_user_id(user.id, :admin)

      event =
        Repo.one(
          from e in Audit.Event,
            where: e.action == "admin.granted" and e.target_id == ^user.id,
            order_by: [desc: e.id],
            limit: 1
        )

      assert event.metadata == %{"reactivated" => true, "role" => "admin"}
    end

    test "writes a compact audit event" do
      user = user_fixture()

      assert {:ok, _admin} = Admin.grant_by_user_id(user.id, :admin)

      event = Repo.one(Audit.Event)
      assert event.type == :auth
      assert event.action == "admin.granted"
      assert event.actor_admin_id == nil
      assert event.actor_label == "cli"
      assert event.target_type == "user"
      assert event.target_id == user.id
      assert event.target_label == user.username
      assert event.metadata == %{"role" => "admin"}
    end
  end

  describe "revoke_by_user_id/1" do
    test "deactivates the admin and audits the revocation" do
      user = user_fixture()
      assert {:ok, _admin} = Admin.grant_by_user_id(user.id, :admin)

      assert {:ok, %AdminRecord{active: false}} = Admin.revoke_by_user_id(user.id)

      event = Repo.get_by(Audit.Event, action: "admin.revoked")
      assert event.target_id == user.id
      assert event.metadata == %{"role" => "admin"}
    end

    test "is idempotent when the admin is already inactive" do
      user = user_fixture()
      assert {:ok, _admin} = Admin.grant_by_user_id(user.id, :admin)
      assert {:ok, _admin} = Admin.revoke_by_user_id(user.id)

      assert {:ok, %AdminRecord{active: false}} = Admin.revoke_by_user_id(user.id)
      assert Repo.aggregate(Audit.Event, :count, :id) == 2
    end

    test "returns an error for a user without an admin record" do
      user = user_fixture()

      assert {:error, :not_found} = Admin.revoke_by_user_id(user.id)
    end

    test "rejects invalid user ids" do
      assert {:error, :invalid_user_id} = Admin.revoke_by_user_id("1")
    end
  end

  describe "list/0" do
    test "lists admins with their users preloaded" do
      first = user_fixture()
      second = user_fixture()

      assert {:ok, _admin} = Admin.grant_by_user_id(first.id, :moderator)
      assert {:ok, _admin} = Admin.grant_by_user_id(second.id, :admin)

      assert [%AdminRecord{user: %{id: first_id}}, %AdminRecord{user: %{id: second_id}}] =
               Admin.list()

      assert first_id == first.id
      assert second_id == second.id
    end
  end

  describe "get_active_admin_for_user/1" do
    test "returns an active admin" do
      user = user_fixture()
      assert {:ok, admin} = Admin.grant_by_user_id(user.id, :moderator)

      assert %AdminRecord{id: id, user: %{id: user_id}} = Admin.get_active_admin_for_user(user)
      assert id == admin.id
      assert user_id == user.id
    end

    test "does not return an inactive admin" do
      user = user_fixture()
      assert {:ok, _admin} = Admin.grant_by_user_id(user.id, :moderator)
      assert {:ok, _admin} = Admin.revoke_by_user_id(user.id)

      assert Admin.get_active_admin_for_user(user) == nil
    end

    test "returns nil for a user without an admin record" do
      assert Admin.get_active_admin_for_user(user_fixture()) == nil
    end
  end
end
