defmodule LuxpkgsWeb.AdminLive.PackagesTest do
  use LuxpkgsWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Luxpkgs.AccountsFixtures
  import Luxpkgs.AdminFixtures
  import Luxpkgs.PackagesFixtures

  alias Luxpkgs.Audit
  alias Luxpkgs.Packages.Package
  alias Luxpkgs.Repo

  defp admin_conn(conn, role) do
    user = user_fixture()
    admin_fixture(%{user: user, role: role})

    conn
    |> log_in_user(user)
    |> put_session(:admin_totp_verified_at, System.os_time(:second))
  end

  test "redirects non-admins", %{conn: conn} do
    user = user_fixture()

    conn =
      conn
      |> log_in_user(user)
      |> put_session(:admin_totp_verified_at, System.os_time(:second))

    assert {:error, {:redirect, %{to: "/"}}} = live(conn, ~p"/admin/packages")
  end

  test "lists active and hidden packages", %{conn: conn} do
    owner = user_fixture()
    scope = user_scope_fixture(owner)
    active = package_fixture(scope, %{name: "listed_active"})
    hidden = package_fixture(scope, %{name: "listed_hidden"})
    hidden |> Ecto.Changeset.change(status: :hidden) |> Repo.update!()

    {:ok, _lv, html} = live(admin_conn(conn, :moderator), ~p"/admin/packages")

    assert html =~ active.name
    assert html =~ hidden.name
    assert html =~ "Hidden"
  end

  test "filters by status and owner search", %{conn: conn} do
    owner = user_fixture()
    scope = user_scope_fixture(owner)
    active = package_fixture(scope, %{name: "filter_active"})
    hidden = package_fixture(scope, %{name: "filter_hidden"})
    hidden |> Ecto.Changeset.change(status: :hidden) |> Repo.update!()

    conn = admin_conn(conn, :moderator)
    {:ok, _lv, html} = live(conn, ~p"/admin/packages?status=hidden")

    assert html =~ hidden.name
    refute html =~ active.name

    {:ok, _lv, html} = live(conn, ~p"/admin/packages?q=#{owner.username}")

    assert html =~ active.name
    assert html =~ hidden.name
  end

  test "moderators can hide and unhide packages", %{conn: conn} do
    owner = user_fixture()
    scope = user_scope_fixture(owner)
    package = package_fixture(scope, %{name: "hide_me"})

    {:ok, lv, _html} = live(admin_conn(conn, :moderator), ~p"/admin/packages")

    lv
    |> element("button[phx-click='hide'][phx-value-id='#{package.id}']")
    |> render_click()

    assert Repo.get!(Package, package.id).status == :hidden
    assert [%{action: "package.hidden"}] = Audit.list_events()

    lv
    |> element("button[phx-click='unhide'][phx-value-id='#{package.id}']")
    |> render_click()

    assert Repo.get!(Package, package.id).status == :active
  end

  test "moderators do not see feature actions", %{conn: conn} do
    owner = user_fixture()
    package_fixture(user_scope_fixture(owner), %{name: "not_featured"})

    {:ok, _lv, html} = live(admin_conn(conn, :moderator), ~p"/admin/packages")

    refute html =~ "phx-click=\"feature\""
  end

  test "admins can feature and unfeature packages", %{conn: conn} do
    owner = user_fixture()
    package = package_fixture(user_scope_fixture(owner), %{name: "feature_me"})

    {:ok, lv, _html} = live(admin_conn(conn, :admin), ~p"/admin/packages")

    lv
    |> element("button[phx-click='feature'][phx-value-id='#{package.id}']")
    |> render_click()

    assert Repo.get!(Package, package.id).featured_at

    lv
    |> element("button[phx-click='unfeature'][phx-value-id='#{package.id}']")
    |> render_click()

    refute Repo.get!(Package, package.id).featured_at
  end
end
