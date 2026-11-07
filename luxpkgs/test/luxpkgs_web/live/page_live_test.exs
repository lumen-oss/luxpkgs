defmodule LuxpkgsWeb.PageLiveTest do
  use LuxpkgsWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Luxpkgs.AccountsFixtures
  import Luxpkgs.AdminFixtures
  import Luxpkgs.PackagesFixtures

  alias Luxpkgs.Packages

  test "shows curated featured packages when present", %{conn: conn} do
    scope = user_scope_fixture()
    admin = admin_fixture(%{role: :admin})
    curated = package_fixture(scope, %{name: "curated_package"})
    popular = package_fixture(scope, %{name: "popular_package"})
    release = release_fixture(scope, popular)
    Enum.each(1..3, fn _ -> Packages.increment_release_download_count(release) end)

    assert {:ok, _} = Packages.feature_package(admin, curated)

    {:ok, view, _html} = live(conn, ~p"/")

    featured_html = view |> element("#featured-packages") |> render()
    assert featured_html =~ "curated_package"
    refute featured_html =~ "popular_package"
  end

  test "falls back to popular packages when none are curated", %{conn: conn} do
    scope = user_scope_fixture()
    popular = package_fixture(scope, %{name: "popular_package"})
    release = release_fixture(scope, popular)
    Enum.each(1..3, fn _ -> Packages.increment_release_download_count(release) end)

    {:ok, view, _html} = live(conn, ~p"/")

    featured_html = view |> element("#featured-packages") |> render()
    assert featured_html =~ "popular_package"
  end
end
