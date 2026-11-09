defmodule Mix.Tasks.Luxpkgs.Users.ResetTotpTest do
  use Luxpkgs.DataCase, async: false

  import ExUnit.CaptureIO
  import Luxpkgs.AccountsFixtures

  alias Luxpkgs.Accounts
  alias Luxpkgs.Accounts.TOTP
  alias Luxpkgs.Audit
  alias Luxpkgs.Repo

  describe "luxpkgs.users.reset_totp" do
    test "clears TOTP, revokes sessions, and audits the action" do
      user = user_fixture()
      :ok = TOTP.enable(user)
      _codes = TOTP.generate_backup_codes(user)
      _token = Accounts.generate_user_session_token(user)

      output = capture_io(fn -> reset(user.id) end)

      assert output =~ "TOTP reset for user #{user.id}"
      assert output =~ "1 session(s) revoked"
      assert TOTP.secret(user) == nil
      assert TOTP.backup_codes_remaining(user) == 0
      assert Accounts.list_user_tokens(user) == []

      event = Repo.get_by(Audit.Event, action: "user.totp_reset")
      assert event.type == :user
      assert event.actor_label == "cli"
      assert event.target_id == user.id
    end

    test "is idempotent when TOTP is already disabled" do
      user = user_fixture()

      output = capture_io(fn -> reset(user.id) end)

      assert output =~ "TOTP reset"
      assert output =~ "0 session(s) revoked"
    end

    test "requires --user-id" do
      assert_raise Mix.Error, ~r/Missing --user-id/, fn ->
        Mix.Tasks.Luxpkgs.Users.ResetTotp.run([])
      end
    end

    test "rejects a non-positive id" do
      assert_raise Mix.Error, ~r/positive integer/, fn -> reset(0) end
    end

    test "rejects unknown users" do
      assert_raise Mix.Error, ~r/No user exists with that ID/, fn -> reset(999_999) end
    end

    test "rejects unexpected arguments" do
      assert_raise Mix.Error, ~r/Unexpected arguments/, fn ->
        Mix.Tasks.Luxpkgs.Users.ResetTotp.run(["extra"])
      end
    end
  end

  defp reset(id), do: Mix.Tasks.Luxpkgs.Users.ResetTotp.run(["--user-id", Integer.to_string(id)])
end
