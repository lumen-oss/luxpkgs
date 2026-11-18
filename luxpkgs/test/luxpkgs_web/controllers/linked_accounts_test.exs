defmodule LuxpkgsWeb.LinkedAccountsControllerTest do
  use LuxpkgsWeb.ConnCase, async: true

  import Luxpkgs.AccountsFixtures

  describe "create/2" do
    test "redirects to the login page when not logged in", %{conn: conn} do
      conn = post(conn, ~p"/settings/identities/github")

      assert redirected_to(conn) == ~p"/login"
    end

    test "starts a github link and stores the intent", %{conn: conn} do
      user = user_fixture()

      conn =
        conn
        |> log_in_user(user)
        |> post(~p"/settings/identities/github")

      assert redirected_to(conn) == ~p"/auth/github"
      assert get_session(conn, :oauth_link_user_id) == user.id
      assert is_integer(get_session(conn, :oauth_link_at))
    end

    test "rejects a blank atproto handle", %{conn: conn} do
      conn =
        conn
        |> log_in_user(user_fixture())
        |> post(~p"/settings/identities/atproto", %{"handle" => "  "})

      assert redirected_to(conn) == ~p"/settings"

      assert Phoenix.Flash.get(conn.assigns.flash, :error) ==
               "Could not sign in with that handle."

      refute get_session(conn, :oauth_link_user_id)
    end

    test "requires a recent login", %{conn: conn} do
      user = user_fixture()

      conn =
        conn
        |> log_in_user(user,
          token_authenticated_at: DateTime.add(DateTime.utc_now(:second), -11, :minute)
        )
        |> post(~p"/settings/identities/github")

      assert redirected_to(conn) == ~p"/settings"

      assert Phoenix.Flash.get(conn.assigns.flash, :error) ==
               "Please re-authenticate to link an account."

      refute get_session(conn, :oauth_link_user_id)
    end
  end

  describe "delete/2" do
    test "redirects to the login page when not logged in", %{conn: conn} do
      conn = delete(conn, ~p"/settings/identities/github")

      assert redirected_to(conn) == ~p"/login"
    end

    test "unlinks a linked account", %{conn: conn} do
      user = user_fixture()

      assert {:ok, :linked} =
               Luxpkgs.Accounts.link_identity(
                 user,
                 Luxpkgs.AtpOauth.auth("did:plc:delete1", "delete.bsky.social")
               )

      conn =
        conn
        |> log_in_user(user)
        |> delete(~p"/settings/identities/atproto")

      assert redirected_to(conn) == ~p"/settings"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) == "Account unlinked."

      refute Luxpkgs.Repo.get_by(Luxpkgs.Accounts.UserIdentity,
               user_id: user.id,
               provider: "atproto"
             )
    end

    test "refuses to unlink the last account", %{conn: conn} do
      user = user_fixture()

      conn = conn |> log_in_user(user) |> delete(~p"/settings/identities/github")

      assert redirected_to(conn) == ~p"/settings"

      assert Phoenix.Flash.get(conn.assigns.flash, :error) ==
               "You must keep at least one linked account."

      assert Luxpkgs.Repo.get_by(Luxpkgs.Accounts.UserIdentity,
               user_id: user.id,
               provider: "github"
             )
    end

    test "requires a recent login", %{conn: conn} do
      user = user_fixture()

      conn =
        conn
        |> log_in_user(user,
          token_authenticated_at: DateTime.add(DateTime.utc_now(:second), -11, :minute)
        )
        |> delete(~p"/settings/identities/github")

      assert redirected_to(conn) == ~p"/settings"

      assert Phoenix.Flash.get(conn.assigns.flash, :error) ==
               "Please re-authenticate to link an account."
    end
  end
end
