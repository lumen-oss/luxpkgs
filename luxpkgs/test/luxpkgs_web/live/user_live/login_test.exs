defmodule LuxpkgsWeb.UserLive.LoginTest do
  use LuxpkgsWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Luxpkgs.AccountsFixtures

  describe "login page" do
    test "renders login page with OAuth provider", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/login")

      assert html =~ "Choose an OAuth Provider"
      assert html =~ "GitHub"
      assert html =~ "AT Protocol"
      assert html =~ ~s(id="atproto-login")
      assert html =~ ~s(name="handle")
    end
  end

  describe "re-authentication (sudo mode)" do
    setup %{conn: conn} do
      user = user_fixture()
      %{user: user, conn: log_in_user(conn, user)}
    end

    test "shows reauthentication message when logged in", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/login")

      assert html =~ "You need to reauthenticate"
    end
  end
end
