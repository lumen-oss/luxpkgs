defmodule LuxpkgsWeb.PackageLive.ShowTest do
  use LuxpkgsWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Luxpkgs.AccountsFixtures
  import Luxpkgs.PackagesFixtures

  alias Luxpkgs.Repo

  defp set_status!(package, status, note \\ nil) do
    package
    |> Ecto.Changeset.change(status: status, moderation_note: note)
    |> Repo.update!()
  end

  test "renders not found for an unknown package", %{conn: conn} do
    {:ok, _lv, html} = live(conn, ~p"/package/does-not-exist")

    assert html =~ "Package not found"
  end

  test "hidden packages are not found for anonymous visitors", %{conn: conn} do
    package = package_fixture(user_scope_fixture()) |> set_status!(:hidden)

    {:ok, _lv, html} = live(conn, ~p"/package/#{package.name}")

    assert html =~ "Package not found"
  end

  test "hidden packages are not found for other users", %{conn: conn} do
    package = package_fixture(user_scope_fixture()) |> set_status!(:hidden)
    %{conn: conn} = register_and_log_in_user(%{conn: conn})

    {:ok, _lv, html} = live(conn, ~p"/package/#{package.name}")

    assert html =~ "Package not found"
  end

  test "owners see a status banner and no download links", %{conn: conn} do
    %{conn: conn, user: user} = register_and_log_in_user(%{conn: conn})
    package = package_fixture(user_scope_fixture(user)) |> set_status!(:hidden, "Contains spam")

    {:ok, _lv, html} = live(conn, ~p"/package/#{package.name}")

    assert html =~ package.name
    assert html =~ "This package is hidden."
    assert html =~ "Contains spam"
    refute html =~ "Download Latest"
  end

  test "owners can yank and unyank a release", %{conn: conn} do
    %{conn: conn, user: user} = register_and_log_in_user(%{conn: conn})
    scope = user_scope_fixture(user)
    package = package_fixture(scope)
    release = release_fixture(scope, package)
    release_id = release.id

    {:ok, lv, html} = live(conn, ~p"/package/#{package.name}")
    assert html =~ "Yank"

    lv
    |> element("button[phx-click='yank_release'][phx-value-id='#{release_id}']")
    |> render_click()

    assert Repo.get!(Luxpkgs.Packages.Release, release_id).yanked_at
    assert render(lv) =~ "Unyank"

    lv
    |> element("button[phx-click='unyank_release'][phx-value-id='#{release_id}']")
    |> render_click()

    refute Repo.get!(Luxpkgs.Packages.Release, release_id).yanked_at
  end

  test "yanked releases are marked and skipped as the latest version", %{conn: conn} do
    %{conn: conn, user: user} = register_and_log_in_user(%{conn: conn})
    scope = user_scope_fixture(user)
    package = package_fixture(scope)
    release_fixture(scope, package, version: "1.0.0")

    release_fixture(scope, package,
      version: "2.0.0",
      yanked_at: DateTime.utc_now() |> DateTime.truncate(:second)
    )

    {:ok, _lv, html} = live(conn, ~p"/package/#{package.name}")

    assert html =~ "v1.0.0"
    assert html =~ "Yanked"
    refute html =~ "v2.0.0</a>"
  end
end
