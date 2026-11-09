defmodule LuxpkgsWeb.AdminLive.PackagesTest do
  use LuxpkgsWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Luxpkgs.AccountsFixtures
  import Luxpkgs.AdminFixtures
  import Luxpkgs.PackagesFixtures

  alias Luxpkgs.Audit
  alias Luxpkgs.Packages.Package
  alias Luxpkgs.Repo

  defp admin_conn(conn, role, verified_at \\ System.os_time(:second)) do
    user = user_fixture()
    admin_fixture(%{user: user, role: role})

    conn
    |> log_in_user(user)
    |> put_session(:admin_totp_verified_at, verified_at)
  end

  test "redirects non-admins", %{conn: conn} do
    user = user_fixture()

    conn =
      conn
      |> log_in_user(user)
      |> put_session(:admin_totp_verified_at, System.os_time(:second))

    assert {:error, {:redirect, %{to: "/"}}} = live(conn, ~p"/admin/packages")
  end

  test "lists packages in every status", %{conn: conn} do
    owner = user_fixture()
    scope = user_scope_fixture(owner)
    active = package_fixture(scope, %{name: "listed_active"})
    hidden = package_fixture(scope, %{name: "listed_hidden"})
    hidden |> Ecto.Changeset.change(status: :hidden) |> Repo.update!()
    removed = package_fixture(scope, %{name: "listed_removed"})
    removed |> Ecto.Changeset.change(status: :removed) |> Repo.update!()

    {:ok, lv, html} = live(admin_conn(conn, :moderator), ~p"/admin/packages")

    assert html =~ active.name
    assert html =~ hidden.name
    assert html =~ removed.name
    assert has_element?(lv, "#package-card-#{removed.id} .badge-error")
    assert has_element?(lv, "nav.dock")
    assert has_element?(lv, "a[aria-current='page'][href='/admin/packages']")
  end

  test "filters by status and owner search", %{conn: conn} do
    owner = user_fixture()
    scope = user_scope_fixture(owner)
    active = package_fixture(scope, %{name: "filter_active"})
    hidden = package_fixture(scope, %{name: "filter_hidden"})
    hidden |> Ecto.Changeset.change(status: :hidden) |> Repo.update!()
    removed = package_fixture(scope, %{name: "filter_removed"})
    removed |> Ecto.Changeset.change(status: :removed) |> Repo.update!()

    conn = admin_conn(conn, :moderator)
    {:ok, _lv, html} = live(conn, ~p"/admin/packages?status=hidden")

    assert html =~ hidden.name
    refute html =~ active.name
    refute html =~ removed.name

    {:ok, _lv, html} = live(conn, ~p"/admin/packages?status=removed")

    assert html =~ removed.name
    refute html =~ active.name
    refute html =~ hidden.name

    {:ok, _lv, html} = live(conn, ~p"/admin/packages?q=#{owner.username}")

    assert html =~ active.name
    assert html =~ hidden.name
    assert html =~ removed.name
  end

  test "moderators can hide and unhide packages", %{conn: conn} do
    owner = user_fixture()
    scope = user_scope_fixture(owner)
    package = package_fixture(scope, %{name: "hide_me"})

    {:ok, lv, _html} = live(admin_conn(conn, :moderator), ~p"/admin/packages")

    lv
    |> element("#package-row-#{package.id} button[phx-click='hide']")
    |> render_click()

    assert Repo.get!(Package, package.id).status == :hidden
    assert [%{action: "package.hidden"}] = Audit.list_events()

    lv
    |> element("#package-row-#{package.id} button[phx-click='unhide']")
    |> render_click()

    assert Repo.get!(Package, package.id).status == :active
  end

  test "admins can remove and restore packages", %{conn: conn} do
    owner = user_fixture()
    package = package_fixture(user_scope_fixture(owner), %{name: "remove_me"})

    {:ok, lv, _html} = live(admin_conn(conn, :admin), ~p"/admin/packages")

    lv
    |> element("#package-row-#{package.id} button[phx-click='remove']")
    |> render_click()

    assert Repo.get!(Package, package.id).status == :removed
    assert Enum.any?(Audit.list_events(), &(&1.action == "package.removed"))

    lv
    |> element("#package-row-#{package.id} button[phx-click='restore']")
    |> render_click()

    assert Repo.get!(Package, package.id).status == :active
    assert Enum.any?(Audit.list_events(), &(&1.action == "package.restored"))
  end

  test "moderators do not see remove or restore actions", %{conn: conn} do
    owner = user_fixture()
    package = package_fixture(user_scope_fixture(owner), %{name: "moderator_remove"})
    removed = package_fixture(user_scope_fixture(owner), %{name: "moderator_restore"})
    removed |> Ecto.Changeset.change(status: :removed) |> Repo.update!()

    {:ok, _lv, html} = live(admin_conn(conn, :moderator), ~p"/admin/packages")

    assert html =~ package.name
    assert html =~ removed.name
    refute html =~ ~s(phx-click="remove")
    refute html =~ ~s(phx-click="restore")
  end

  test "removing a package requires recent TOTP verification", %{conn: conn} do
    owner = user_fixture()
    package = package_fixture(user_scope_fixture(owner), %{name: "fresh_remove"})
    conn = admin_conn(conn, :admin, System.os_time(:second) - 601)

    {:ok, lv, _html} = live(conn, ~p"/admin/packages")

    assert {:error, {:redirect, %{to: "/admin/verify"}}} =
             lv
             |> element("#package-row-#{package.id} button[phx-click='remove']")
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
    |> element("#package-row-#{package.id} button[phx-click='feature']")
    |> render_click()

    assert Repo.get!(Package, package.id).featured_at

    lv
    |> element("#package-row-#{package.id} button[phx-click='unfeature']")
    |> render_click()

    refute Repo.get!(Package, package.id).featured_at
  end
end
