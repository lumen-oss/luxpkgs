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
    package = package_fixture(user_scope_fixture(user)) |> set_status!(:yanked, "Contains spam")

    {:ok, _lv, html} = live(conn, ~p"/package/#{package.name}")

    assert html =~ package.name
    assert html =~ "This package is yanked."
    assert html =~ "Contains spam"
    refute html =~ "Download Latest"
  end
end
