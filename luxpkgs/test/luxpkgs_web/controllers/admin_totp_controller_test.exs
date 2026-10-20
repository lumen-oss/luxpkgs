defmodule LuxpkgsWeb.AdminTotpControllerTest do
  use LuxpkgsWeb.ConnCase, async: true

  import Luxpkgs.AccountsFixtures
  import Luxpkgs.AdminFixtures

  alias Luxpkgs.Accounts
  alias Luxpkgs.Audit
  alias Luxpkgs.Repo

  test "redirects unauthenticated users to login", %{conn: conn} do
    conn = get(conn, ~p"/admin/verify")

    assert redirected_to(conn) == ~p"/login"
  end

  test "redirects users without admin access to home", %{conn: conn} do
    user = user_fixture()

    conn =
      conn
      |> log_in_user(user)
      |> get(~p"/admin/verify")

    assert redirected_to(conn) == ~p"/"
    assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "Admin access required"
  end

  test "redirects revoked admins to home", %{conn: conn} do
    user = user_fixture()
    admin_fixture(%{user: user, active: false})

    conn =
      conn
      |> log_in_user(user)
      |> get(~p"/admin/verify")

    assert redirected_to(conn) == ~p"/"
    assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "Admin access required"
  end

  test "renders the verification page for admins without a fresh check", %{conn: conn} do
    user = user_fixture()
    admin_fixture(%{user: user})

    conn =
      conn
      |> log_in_user(user)
      |> get(~p"/admin/verify")

    assert html_response(conn, 200) =~ "Admin verification"
  end

  test "redirects to the dashboard when the session is fresh", %{conn: conn} do
    user = user_fixture()
    admin_fixture(%{user: user})

    conn =
      conn
      |> log_in_user(user)
      |> put_session(:admin_totp_verified_at, System.os_time(:second))
      |> get(~p"/admin/verify")

    assert redirected_to(conn) == ~p"/admin"
  end

  test "verifies a valid code, stores freshness, and audits the login", %{conn: conn} do
    user = user_fixture()
    admin = admin_fixture(%{user: user, role: :admin})
    conn = log_in_user(conn, user)
    code = NimbleTOTP.verification_code(Accounts.TOTP.secret(user))

    conn = post(conn, ~p"/admin/verify", %{"code" => code})

    assert redirected_to(conn) == ~p"/admin"
    assert is_integer(get_session(conn, :admin_totp_verified_at))
    assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "verified"

    assert Repo.get_by(Audit.Event,
             action: "admin.totp_verified",
             actor_admin_id: admin.id
           )
  end

  test "rejects an invalid code", %{conn: conn} do
    user = user_fixture()
    admin_fixture(%{user: user})

    conn =
      conn
      |> log_in_user(user)
      |> post(~p"/admin/verify", %{"code" => "not-a-code"})

    assert redirected_to(conn) == ~p"/admin/verify"
    assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "Invalid verification code"
    refute get_session(conn, :admin_totp_verified_at)
  end

  test "rejects a missing code", %{conn: conn} do
    user = user_fixture()
    admin_fixture(%{user: user})

    conn =
      conn
      |> log_in_user(user)
      |> post(~p"/admin/verify", %{})

    assert redirected_to(conn) == ~p"/admin/verify"
    assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "Enter a verification code"
  end
end
