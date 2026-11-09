defmodule Mix.Tasks.Luxpkgs.UsersTest do
  use Luxpkgs.DataCase, async: false

  import ExUnit.CaptureIO
  import Luxpkgs.AccountsFixtures
  import Luxpkgs.AdminFixtures

  alias Luxpkgs.Accounts
  alias Luxpkgs.Accounts.TOTP

  describe "luxpkgs.users.find" do
    test "finds a user by id" do
      user = user_fixture()

      output = capture_io(fn -> find(["--id", Integer.to_string(user.id)]) end)

      assert output =~ "id:"
      assert output =~ Integer.to_string(user.id)
      assert output =~ user.username
      assert output =~ user.email
    end

    test "finds a user by email and by username" do
      user = user_fixture()

      email_output = capture_io(fn -> find(["--email", user.email]) end)
      username_output = capture_io(fn -> find(["--username", user.username]) end)

      assert email_output =~ Integer.to_string(user.id)
      assert username_output =~ Integer.to_string(user.id)
    end

    test "shows suspension, admin role, and TOTP state" do
      actor = admin_fixture(%{role: :admin})
      user = user_fixture()
      {:ok, user, _tokens} = Accounts.suspend_user(actor, user, "spam")
      :ok = TOTP.enable(user)

      output = capture_io(fn -> find(["--id", Integer.to_string(user.id)]) end)

      assert output =~ "suspended (spam)"
      assert output =~ "totp:"
      assert output =~ "enabled"
    end

    test "shows an active admin role" do
      user = user_fixture()
      admin_fixture(%{user: user, role: :moderator})

      output = capture_io(fn -> find(["--id", Integer.to_string(user.id)]) end)

      assert output =~ "moderator (active)"
    end

    test "rejects a missing selector" do
      assert_raise Mix.Error, ~r/Provide one of/, fn -> find([]) end
    end

    test "rejects multiple selectors" do
      assert_raise Mix.Error, ~r/Provide only one of/, fn ->
        find(["--id", "1", "--email", "user@example.com"])
      end
    end

    test "rejects a non-positive id" do
      assert_raise Mix.Error, ~r/positive integer/, fn -> find(["--id", "0"]) end
    end

    test "rejects unknown users" do
      assert_raise Mix.Error, ~r/No user found with ID 999999/, fn ->
        find(["--id", "999999"])
      end
    end

    test "rejects unexpected arguments" do
      assert_raise Mix.Error, ~r/Unexpected arguments/, fn -> find(["extra"]) end
    end
  end

  defp find(args), do: Mix.Tasks.Luxpkgs.Users.Find.run(args)
end
