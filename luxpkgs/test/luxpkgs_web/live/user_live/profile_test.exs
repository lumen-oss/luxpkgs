defmodule LuxpkgsWeb.UserLive.ProfileTest do
  use LuxpkgsWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Luxpkgs.AccountsFixtures
  import Luxpkgs.PackagesFixtures

  describe "Public profile page" do
    test "renders the user's profile with their packages", %{conn: conn} do
      user = user_fixture()
      scope = user_scope_fixture(user)
      package = package_fixture(scope, %{name: "my_package"})
      release = release_fixture(scope, package)
      Luxpkgs.Repo.update_all(Luxpkgs.Packages.Release, set: [download_count: 1200])

      {:ok, _lv, html} = live(conn, ~p"/users/#{user.username}")

      assert html =~ user.username
      assert html =~ "my_package"
      assert html =~ "1.2K"
      assert html =~ to_string(release.version)
    end

    test "renders the user's bio", %{conn: conn} do
      user = user_fixture()
      {:ok, user} = Luxpkgs.Accounts.update_bio(user, "Maker of Lua tools")

      {:ok, _lv, html} = live(conn, ~p"/users/#{user.username}")

      assert html =~ "Maker of Lua tools"
    end

    test "does not expose the user's email", %{conn: conn} do
      user = user_fixture()

      {:ok, _lv, html} = live(conn, ~p"/users/#{user.username}")

      refute html =~ user.email
    end

    test "renders an empty state when the user has no packages", %{conn: conn} do
      user = user_fixture()

      {:ok, _lv, html} = live(conn, ~p"/users/#{user.username}")

      assert html =~ "has not published any packages yet"
    end

    test "renders a publish CTA on the current user's empty profile", %{conn: conn} do
      user = user_fixture()

      {:ok, _lv, html} =
        conn
        |> log_in_user(user)
        |> live(~p"/users/#{user.username}")

      assert html =~ "You have not published any packages yet"
      assert html =~ "Get started with the docs"
      assert html =~ "lux CLI"
    end

    test "renders not found for an unknown user", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/users/does-not-exist")

      assert html =~ "User not found"
    end

    test "paginates the user's packages", %{conn: conn} do
      user = user_fixture()
      scope = user_scope_fixture(user)

      for i <- 1..13 do
        package_fixture(scope, %{name: "pkg_#{i}"})
      end

      {:ok, _lv, html} = live(conn, ~p"/users/#{user.username}")

      assert html =~ "Showing 12 of 13 packages"

      {:ok, _lv, page2} = live(conn, ~p"/users/#{user.username}?page=2")

      assert page2 =~ "Showing 1 of 13 packages"
    end

    test "sorts packages by name", %{conn: conn} do
      user = user_fixture()
      scope = user_scope_fixture(user)

      for name <- ~w(zeta_pkg alpha_pkg bravo_pkg) do
        package_fixture(scope, %{name: name})
      end

      {:ok, _lv, html} = live(conn, ~p"/users/#{user.username}?sort=name")

      alpha = :binary.match(html, "alpha_pkg")
      bravo = :binary.match(html, "bravo_pkg")
      zeta = :binary.match(html, "zeta_pkg")

      assert elem(alpha, 0) < elem(bravo, 0)
      assert elem(bravo, 0) < elem(zeta, 0)
    end

    test "owners see their hidden packages with a badge", %{conn: conn} do
      user = user_fixture()
      scope = user_scope_fixture(user)
      package = package_fixture(scope, %{name: "owned_hidden"})
      package |> Ecto.Changeset.change(status: :hidden) |> Luxpkgs.Repo.update!()

      {:ok, _lv, html} =
        conn
        |> log_in_user(user)
        |> live(~p"/users/#{user.username}")

      assert html =~ package.name
      assert html =~ "Hidden"
    end

    test "owners see their removed packages with a badge", %{conn: conn} do
      user = user_fixture()
      scope = user_scope_fixture(user)
      package = package_fixture(scope, %{name: "owned_removed"})
      package |> Ecto.Changeset.change(status: :removed) |> Luxpkgs.Repo.update!()

      {:ok, _lv, html} =
        conn
        |> log_in_user(user)
        |> live(~p"/users/#{user.username}")

      assert html =~ package.name
      assert html =~ "Removed"
      assert html =~ "badge badge-error badge-sm"
    end

    test "hidden packages stay private on other users' profiles", %{conn: conn} do
      user = user_fixture()
      scope = user_scope_fixture(user)
      package = package_fixture(scope, %{name: "private_hidden"})
      package |> Ecto.Changeset.change(status: :hidden) |> Luxpkgs.Repo.update!()

      {:ok, _lv, html} = live(conn, ~p"/users/#{user.username}")

      refute html =~ package.name
    end
  end

  describe "Package show page" do
    test "links the author card to the profile page", %{conn: conn} do
      user = user_fixture()
      scope = user_scope_fixture(user)
      package = package_fixture(scope, %{name: "author_pkg"})
      release_fixture(scope, package)

      {:ok, _lv, html} = live(conn, ~p"/package/author_pkg")

      assert html =~ ~p"/users/#{user.username}"
    end
  end
end
