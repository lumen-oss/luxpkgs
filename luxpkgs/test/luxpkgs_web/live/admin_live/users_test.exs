defmodule LuxpkgsWeb.AdminLive.UsersTest do
  use LuxpkgsWeb.ConnCase, async: true

  import Ecto.Query
  import Phoenix.LiveViewTest
  import Luxpkgs.AccountsFixtures
  import Luxpkgs.AdminFixtures
  import Luxpkgs.ModerationFixtures
  import Luxpkgs.PackagesFixtures

  alias Luxpkgs.Accounts
  alias Luxpkgs.Repo

  defp admin_conn(conn, role, verified_at \\ System.os_time(:second)) do
    user = user_fixture()
    admin_fixture(%{user: user, role: role})

    conn
    |> log_in_user(user)
    |> put_session(:admin_totp_verified_at, verified_at)
  end

  describe "users list" do
    test "moderators are redirected and do not see the users nav item", %{conn: conn} do
      conn = admin_conn(conn, :moderator)

      assert {:error, {:redirect, %{to: "/admin"}}} = live(conn, ~p"/admin/users")

      {:ok, lv, _html} = live(conn, ~p"/admin")
      refute has_element?(lv, "a[href='/admin/users']")
    end

    test "admins see the users list with package and download totals", %{conn: conn} do
      conn = admin_conn(conn, :admin)
      user = user_fixture()
      username = user.username
      scope = Luxpkgs.Accounts.Scope.for_user(user)

      package = package_fixture(scope, %{name: "listed_pkg_#{user.id}"})
      release = release_fixture(scope, package)

      Repo.update_all(
        from(r in Luxpkgs.Packages.Release, where: r.id == ^release.id),
        inc: [download_count: 42]
      )

      {:ok, lv, html} = live(conn, "/admin/users?" <> URI.encode_query(%{"q" => username}))

      assert html =~ username
      assert html =~ user.email
      assert has_element?(lv, "#user-row-#{user.id}")
      assert has_element?(lv, "a[aria-current='page'][href='/admin/users']")
      assert has_element?(lv, "nav.dock a[href='/admin/users']")
    end

    test "searches username, email, and aka", %{conn: conn} do
      conn = admin_conn(conn, :admin)
      user = user_fixture()
      other = user_fixture()
      term = user.username

      user =
        user
        |> Ecto.Changeset.change(aka: "Aka #{term}")
        |> Repo.update!()

      {:ok, lv, _html} = live(conn, "/admin/users?" <> URI.encode_query(%{"q" => term}))

      assert has_element?(lv, "#user-row-#{user.id}")
      refute has_element?(lv, "#user-row-#{other.id}")

      for query <- [user.email, user.aka] do
        {:ok, lv, _html} = live(conn, "/admin/users?" <> URI.encode_query(%{"q" => query}))
        assert has_element?(lv, "#user-row-#{user.id}")
      end
    end

    test "filters suspended and active users", %{conn: conn} do
      conn = admin_conn(conn, :admin)
      active = user_fixture()
      suspended = user_fixture()
      actor = admin_fixture(%{role: :admin})
      {:ok, suspended, _tokens} = Accounts.suspend_user(actor, suspended, "Spam")

      {:ok, lv, _html} = live(conn, ~p"/admin/users?status=suspended")
      assert has_element?(lv, "#user-row-#{suspended.id}")
      refute has_element?(lv, "#user-row-#{active.id}")

      {:ok, lv, _html} = live(conn, ~p"/admin/users?status=active")
      assert has_element?(lv, "#user-row-#{active.id}")
      refute has_element?(lv, "#user-row-#{suspended.id}")
    end

    test "filters by role and users without a role", %{conn: conn} do
      conn = admin_conn(conn, :admin)
      admin_user = user_fixture()
      admin_fixture(%{user: admin_user, role: :admin})
      moderator_user = user_fixture()
      admin_fixture(%{user: moderator_user, role: :moderator})
      plain_user = user_fixture()

      {:ok, lv, _html} = live(conn, ~p"/admin/users?role=admin")
      assert has_element?(lv, "#user-row-#{admin_user.id}")
      refute has_element?(lv, "#user-row-#{moderator_user.id}")
      refute has_element?(lv, "#user-row-#{plain_user.id}")

      {:ok, lv, _html} = live(conn, ~p"/admin/users?role=none")
      refute has_element?(lv, "#user-row-#{admin_user.id}")
      refute has_element?(lv, "#user-row-#{moderator_user.id}")
      assert has_element?(lv, "#user-row-#{plain_user.id}")
    end

    test "excludes the deleted sentinel unless requested", %{conn: conn} do
      conn = admin_conn(conn, :admin)
      sentinel = Accounts.deleted_user()

      {:ok, lv, _html} = live(conn, ~p"/admin/users")
      refute has_element?(lv, "#user-row-#{sentinel.id}")

      {:ok, lv, _html} = live(conn, ~p"/admin/users?include_deleted=true")
      assert has_element?(lv, "#user-row-#{sentinel.id}")
    end
  end

  describe "user detail" do
    test "shows profile, packages, reports, suspension, and audit events", %{conn: conn} do
      conn = admin_conn(conn, :admin)
      actor_user = user_fixture()
      actor = admin_fixture(%{user: actor_user, role: :admin})

      target =
        user_fixture()
        |> Ecto.Changeset.change(
          username: "detail_user_#{System.unique_integer([:positive])}",
          bio: "A bio"
        )
        |> Repo.update!()

      scope = Luxpkgs.Accounts.Scope.for_user(target)

      active_package = package_fixture(scope, %{name: "detail_active_#{target.id}"})

      hidden_package =
        package_fixture(scope, %{name: "detail_hidden_#{target.id}", status: :hidden})

      release = release_fixture(scope, active_package)

      Repo.update_all(
        from(r in Luxpkgs.Packages.Release, where: r.id == ^release.id),
        inc: [download_count: 9]
      )

      report_fixture(target, active_package)

      {:ok, target, _tokens} = Accounts.suspend_user(actor, target, "Spam and abuse")

      {:ok, lv, html} = live(conn, ~p"/admin/users/#{target.id}")

      assert html =~ target.username
      assert html =~ target.email
      assert html =~ "Spam and abuse"
      assert html =~ "Suspended"
      assert html =~ "Reports filed"
      assert html =~ "by #{actor_user.username}"
      assert has_element?(lv, "#user-package-row-#{active_package.id}")
      assert has_element?(lv, "#user-package-row-#{hidden_package.id}")
      assert has_element?(lv, "#user-package-row-#{hidden_package.id}", "hidden")
    end

    test "shows a not found card for an unknown user", %{conn: conn} do
      conn = admin_conn(conn, :admin)

      {:ok, _lv, html} = live(conn, ~p"/admin/users/999999999")

      assert html =~ "User not found"
    end

    test "suspends a user and disconnects their sessions", %{conn: conn} do
      conn = admin_conn(conn, :admin)
      target = user_fixture()
      token = Accounts.generate_user_session_token(target)
      topic = "users_sessions:#{Base.url_encode64(token)}"
      LuxpkgsWeb.Endpoint.subscribe(topic)

      {:ok, lv, _html} = live(conn, ~p"/admin/users/#{target.id}")

      html =
        lv
        |> element("#suspend-user-form")
        |> render_submit(%{"reason" => "Spam"})

      assert html =~ "User suspended."
      assert html =~ "Suspended"
      assert html =~ "Spam"
      assert Accounts.get_user(target.id).suspension_reason == "Spam"
      refute Accounts.get_user_by_session_token(token)
      assert_receive %Phoenix.Socket.Broadcast{event: "disconnect", topic: ^topic}
    end

    test "rejects suspending yourself", %{conn: conn} do
      user = user_fixture()
      admin_fixture(%{user: user, role: :admin})

      conn =
        conn
        |> log_in_user(user)
        |> put_session(:admin_totp_verified_at, System.os_time(:second))

      {:ok, lv, _html} = live(conn, ~p"/admin/users/#{user.id}")

      assert has_element?(lv, "#suspend-user-form textarea[disabled]")
      assert has_element?(lv, "#suspend-user-form button[disabled]")
      assert render(lv) =~ "You cannot suspend your own account."

      html =
        lv
        |> element("#suspend-user-form")
        |> render_submit(%{"reason" => "Oops"})

      assert html =~ "You cannot suspend your own account."
      refute Accounts.get_user(user.id).suspended_at
    end

    test "requires a fresh second factor before suspending", %{conn: conn} do
      conn = admin_conn(conn, :admin, System.os_time(:second) - 11 * 60)
      target = user_fixture()

      {:ok, lv, _html} = live(conn, ~p"/admin/users/#{target.id}")

      assert {:error, {:redirect, %{to: "/admin/verify"}}} =
               lv
               |> element("#suspend-user-form")
               |> render_submit(%{"reason" => "Spam"})

      refute Accounts.get_user(target.id).suspended_at
    end

    test "unsuspends a user", %{conn: conn} do
      conn = admin_conn(conn, :admin)
      actor = admin_fixture(%{role: :admin})
      target = user_fixture()
      {:ok, target, _tokens} = Accounts.suspend_user(actor, target, "Spam")

      {:ok, lv, _html} = live(conn, ~p"/admin/users/#{target.id}")

      html = lv |> element("button[phx-click='unsuspend']") |> render_click()

      assert html =~ "User unsuspended."
      assert html =~ "This account is active."
      refute Accounts.get_user(target.id).suspended_at
    end
  end
end
