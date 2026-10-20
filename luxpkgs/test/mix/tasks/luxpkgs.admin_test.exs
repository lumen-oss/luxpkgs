defmodule Mix.Tasks.Luxpkgs.AdminTest do
  use Luxpkgs.DataCase, async: false

  import ExUnit.CaptureIO
  import Luxpkgs.AccountsFixtures

  alias Luxpkgs.Admin
  alias Luxpkgs.Admin.Admin, as: AdminRecord
  alias Luxpkgs.Audit
  alias Luxpkgs.Repo

  describe "luxpkgs.admin.grant" do
    test "grants admin access and audits the action" do
      user = user_fixture()

      output =
        capture_io(fn ->
          run_grant(user.id, "admin")
        end)

      assert output =~ "now has the admin role"

      assert %AdminRecord{role: :admin, active: true} =
               Admin.get_active_admin_for_user(user)

      event = Repo.get_by(Audit.Event, action: "admin.granted")
      assert event.actor_label == "cli"
      assert event.target_id == user.id
      assert event.metadata == %{"role" => "admin"}
    end

    test "changes an existing role" do
      user = user_fixture()
      assert {:ok, _admin} = Admin.grant_by_user_id(user.id, :moderator)

      output =
        capture_io(fn ->
          run_grant(user.id, "admin")
        end)

      assert output =~ "now has the admin role"
      assert %AdminRecord{role: :admin} = Admin.get_active_admin_for_user(user)
    end

    test "requires --user-id" do
      assert_raise Mix.Error, ~r/Missing --user-id/, fn ->
        Mix.Tasks.Luxpkgs.Admin.Grant.run(["--role", "admin"])
      end
    end

    test "requires --role" do
      user = user_fixture()

      assert_raise Mix.Error, ~r/Missing --role/, fn ->
        Mix.Tasks.Luxpkgs.Admin.Grant.run(["--user-id", Integer.to_string(user.id)])
      end
    end

    test "rejects unknown roles" do
      user = user_fixture()

      assert_raise Mix.Error, ~r/--role must be admin or moderator/, fn ->
        run_grant(user.id, "owner")
      end
    end

    test "rejects unknown users" do
      assert_raise Mix.Error, ~r/No user exists with that ID/, fn ->
        run_grant(999_999, "admin")
      end
    end
  end

  describe "luxpkgs.admin.revoke" do
    test "revokes access and keeps the admin record" do
      user = user_fixture()
      assert {:ok, _admin} = Admin.grant_by_user_id(user.id, :admin)

      output =
        capture_io(fn ->
          run_revoke(user.id)
        end)

      assert output =~ "is now revoked"
      assert Admin.get_active_admin_for_user(user) == nil
      assert Repo.get_by(AdminRecord, user_id: user.id)
    end

    test "rejects users without an admin record" do
      user = user_fixture()

      assert_raise Mix.Error, ~r/No admin record exists/, fn ->
        run_revoke(user.id)
      end
    end
  end

  describe "luxpkgs.admin.list" do
    test "lists admins and moderators" do
      admin_user = user_fixture()
      moderator_user = user_fixture()
      assert {:ok, _admin} = Admin.grant_by_user_id(admin_user.id, :admin)
      assert {:ok, _admin} = Admin.grant_by_user_id(moderator_user.id, :moderator)

      output =
        capture_io(fn ->
          Mix.Tasks.Luxpkgs.Admin.List.run([])
        end)

      assert output =~ "user_id"
      assert output =~ admin_user.username
      assert output =~ moderator_user.username
      assert output =~ "admin"
      assert output =~ "moderator"
    end

    test "prints a message when there are no admins" do
      output =
        capture_io(fn ->
          Mix.Tasks.Luxpkgs.Admin.List.run([])
        end)

      assert output =~ "No admins."
    end

    test "rejects unexpected arguments" do
      assert_raise Mix.Error, ~r/Unexpected arguments/, fn ->
        Mix.Tasks.Luxpkgs.Admin.List.run(["extra"])
      end
    end
  end

  defp run_grant(user_id, role) do
    Mix.Tasks.Luxpkgs.Admin.Grant.run([
      "--user-id",
      Integer.to_string(user_id),
      "--role",
      role
    ])
  end

  defp run_revoke(user_id) do
    Mix.Tasks.Luxpkgs.Admin.Revoke.run(["--user-id", Integer.to_string(user_id)])
  end
end
