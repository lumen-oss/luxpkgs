defmodule LuxpkgsWeb.AdminLive.DashboardTest do
  use LuxpkgsWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Luxpkgs.AccountsFixtures
  import Luxpkgs.AdminFixtures

  test "redirects users without admin access", %{conn: conn} do
    user = user_fixture()

    conn =
      conn
      |> log_in_user(user)
      |> put_session(:admin_totp_verified_at, System.os_time(:second))

    assert {:error, {:redirect, %{to: "/"}}} = live(conn, ~p"/admin")
  end

  test "redirects admins who have not verified their second factor", %{conn: conn} do
    user = user_fixture()
    admin_fixture(%{user: user})

    conn = log_in_user(conn, user)

    assert {:error, {:redirect, %{to: "/admin/verify"}}} = live(conn, ~p"/admin")
  end

  test "redirects admins with a stale second factor check", %{conn: conn} do
    user = user_fixture()
    admin_fixture(%{user: user})

    conn =
      conn
      |> log_in_user(user)
      |> put_session(:admin_totp_verified_at, System.os_time(:second) - 31 * 60)

    assert {:error, {:redirect, %{to: "/admin/verify"}}} = live(conn, ~p"/admin")
  end

  test "renders the dashboard for an active admin with a fresh check", %{conn: conn} do
    user = user_fixture()
    admin_fixture(%{user: user, role: :admin})

    conn =
      conn
      |> log_in_user(user)
      |> put_session(:admin_totp_verified_at, System.os_time(:second))

    assert {:ok, view, html} = live(conn, ~p"/admin")
    assert html =~ "Dashboard"
    assert html =~ user.username
    assert html =~ "admin"
    assert html =~ "Packages"
    assert html =~ "Recent activity"
    assert has_element?(view, "nav.dock")
    assert has_element?(view, "a[aria-current='page'][href='/admin']")
  end

  test "moderators do not see recent admin activity", %{conn: conn} do
    user = user_fixture()
    admin_fixture(%{user: user, role: :moderator})

    conn =
      conn
      |> log_in_user(user)
      |> put_session(:admin_totp_verified_at, System.os_time(:second))

    {:ok, _view, html} = live(conn, ~p"/admin")

    refute html =~ "Recent activity"
    refute html =~ "Quick actions"
    assert html =~ "Packages"
  end

  test "redirects revoked admins", %{conn: conn} do
    user = user_fixture()
    admin_fixture(%{user: user, active: false})

    conn =
      conn
      |> log_in_user(user)
      |> put_session(:admin_totp_verified_at, System.os_time(:second))

    assert {:error, {:redirect, %{to: "/"}}} = live(conn, ~p"/admin")
  end
end
