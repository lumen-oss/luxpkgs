defmodule LuxpkgsWeb.AdminLive.PackageTest do
  use LuxpkgsWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Luxpkgs.AccountsFixtures
  import Luxpkgs.AdminFixtures
  import Luxpkgs.PackagesFixtures

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
    package_fixture(user_scope_fixture(user), %{name: "private_view"})

    conn =
      conn
      |> log_in_user(user)
      |> put_session(:admin_totp_verified_at, System.os_time(:second))

    assert {:error, {:redirect, %{to: "/"}}} = live(conn, ~p"/admin/packages/1")
  end

  test "shows package details and the selected source", %{conn: conn} do
    owner = user_fixture()
    scope = user_scope_fixture(owner)
    package = package_fixture(scope, %{name: "source_demo"})
    release_fixture(scope, package, %{version: "1.0.0", rockspec: "source_demo_content"})

    {:ok, _lv, html} = live(admin_conn(conn, :moderator), ~p"/admin/packages/#{package.id}")

    assert html =~ "source_demo"
    assert html =~ owner.username
    assert html =~ "source_demo_content"
    assert html =~ "source_demo-1.0.0.rockspec"
    assert html =~ "Source"
    assert html =~ ~s(data-ln="1")
  end

  test "navigates between releases and stops at boundaries", %{conn: conn} do
    owner = user_fixture()
    scope = user_scope_fixture(owner)
    package = package_fixture(scope, %{name: "release_nav"})
    older = release_fixture(scope, package, %{version: "1.0.0", rockspec: "old_source"})
    release_fixture(scope, package, %{version: "2.0.0", rockspec: "new_source"})

    {:ok, lv, html} = live(admin_conn(conn, :moderator), ~p"/admin/packages/#{package.id}")

    assert html =~ "new_source"
    refute html =~ "old_source"

    html = lv |> element("button[phx-value-direction='prev']") |> render_click()

    assert html =~ "old_source"
    assert has_element?(lv, "button[phx-value-direction='prev'][disabled]")

    html = lv |> element("button[phx-value-direction='next']") |> render_click()

    assert html =~ "new_source"
    assert has_element?(lv, "button[phx-value-direction='next'][disabled]")

    html =
      lv
      |> element("form#release-select")
      |> render_change(%{"release" => to_string(older.id)})

    assert html =~ "old_source"
  end

  test "escapes HTML in the source", %{conn: conn} do
    owner = user_fixture()
    scope = user_scope_fixture(owner)
    package = package_fixture(scope, %{name: "escaped_source"})

    release_fixture(scope, package, %{
      version: "1.0.0",
      rockspec: ~s|local x = "<script>alert(1)</script>"|
    })

    {:ok, _lv, html} = live(admin_conn(conn, :moderator), ~p"/admin/packages/#{package.id}")

    assert html =~ "&lt;script&gt;alert(1)&lt;/script&gt;"
    assert html =~ ~s(class="text-primary">local</span>)
    refute html =~ "<script>alert(1)</script>"
  end

  test "keeps the details panel usable when the source is missing", %{conn: conn} do
    owner = user_fixture()
    scope = user_scope_fixture(owner)
    package = package_fixture(scope, %{name: "missing_source"})
    release = release_fixture(scope, package, %{version: "1.0.0", rockspec: "gone"})

    Application.get_env(:luxpkgs, :rockspec_storage)
    |> Path.join(release.rockspec_path)
    |> File.rm!()

    {:ok, _lv, html} = live(admin_conn(conn, :moderator), ~p"/admin/packages/#{package.id}")

    assert html =~ "missing_source"
    assert html =~ "The source file is missing."
    assert html =~ "Package"
  end

  test "shows a message for packages without releases", %{conn: conn} do
    owner = user_fixture()
    package = package_fixture(user_scope_fixture(owner), %{name: "no_releases"})

    {:ok, _lv, html} = live(admin_conn(conn, :moderator), ~p"/admin/packages/#{package.id}")

    assert html =~ "This package has no releases."
  end

  test "moderators can view hidden packages and unhide them", %{conn: conn} do
    owner = user_fixture()
    package = package_fixture(user_scope_fixture(owner), %{name: "hidden_view"})
    package |> Ecto.Changeset.change(status: :hidden) |> Repo.update!()

    {:ok, lv, html} = live(admin_conn(conn, :moderator), ~p"/admin/packages/#{package.id}")

    assert html =~ "hidden_view"
    assert html =~ "hidden"

    lv
    |> element("button[phx-value-action='unhide']")
    |> render_click()

    assert Repo.get!(Package, package.id).status == :active
  end

  test "admins can remove and restore packages from the detail view", %{conn: conn} do
    owner = user_fixture()
    package = package_fixture(user_scope_fixture(owner), %{name: "remove_view"})

    {:ok, lv, _html} = live(admin_conn(conn, :admin), ~p"/admin/packages/#{package.id}")

    lv
    |> element("button[phx-value-action='remove']")
    |> render_click()

    assert Repo.get!(Package, package.id).status == :removed
    assert has_element?(lv, "button[phx-value-action='restore']")

    lv
    |> element("button[phx-value-action='restore']")
    |> render_click()

    assert Repo.get!(Package, package.id).status == :active
  end

  test "moderators do not see remove or restore actions in the detail view", %{conn: conn} do
    owner = user_fixture()
    package = package_fixture(user_scope_fixture(owner), %{name: "mod_remove_view"})
    removed = package_fixture(user_scope_fixture(owner), %{name: "mod_restore_view"})
    removed |> Ecto.Changeset.change(status: :removed) |> Repo.update!()

    {:ok, _lv, html} = live(admin_conn(conn, :moderator), ~p"/admin/packages/#{package.id}")

    refute html =~ ~s(phx-value-action="remove")

    {:ok, _lv, html} = live(admin_conn(conn, :moderator), ~p"/admin/packages/#{removed.id}")

    refute html =~ ~s(phx-value-action="restore")
  end

  test "removing from the detail view requires recent TOTP verification", %{conn: conn} do
    owner = user_fixture()
    package = package_fixture(user_scope_fixture(owner), %{name: "fresh_remove_view"})
    conn = admin_conn(conn, :admin, System.os_time(:second) - 601)

    {:ok, lv, _html} = live(conn, ~p"/admin/packages/#{package.id}")

    assert {:error, {:redirect, %{to: "/admin/verify"}}} =
             lv
             |> element("button[phx-value-action='remove']")
             |> render_click()

    assert Repo.get!(Package, package.id).status == :active
  end

  test "admins can feature packages from the detail view", %{conn: conn} do
    owner = user_fixture()
    package = package_fixture(user_scope_fixture(owner), %{name: "feature_view"})

    {:ok, lv, _html} = live(admin_conn(conn, :admin), ~p"/admin/packages/#{package.id}")

    lv
    |> element("button[phx-value-action='feature']")
    |> render_click()

    assert Repo.get!(Package, package.id).featured_at
  end
end
