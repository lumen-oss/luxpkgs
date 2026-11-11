defmodule LuxpkgsWeb.PackageLive.ShowTest do
  use LuxpkgsWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Luxpkgs.AccountsFixtures
  import Luxpkgs.ModerationFixtures
  import Luxpkgs.PackagesFixtures

  alias Luxpkgs.Moderation
  alias Luxpkgs.Repo
  alias LuxpkgsWeb.RateLimit

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

  test "anonymous visitors are prompted to sign in to report", %{conn: conn} do
    package = package_fixture(user_scope_fixture())

    {:ok, lv, html} = live(conn, ~p"/package/#{package.name}")

    assert has_element?(lv, "button[aria-label='Report package']")
    assert html =~ "Sign in to report this package to the moderators."
    refute has_element?(lv, "#report_package_modal form[phx-submit='report_package']")
  end

  test "owners cannot report their own package", %{conn: conn} do
    %{conn: conn, user: user} = register_and_log_in_user(%{conn: conn})
    package = package_fixture(user_scope_fixture(user))

    {:ok, lv, html} = live(conn, ~p"/package/#{package.name}")

    refute has_element?(lv, "button[aria-label='Report package']")
    refute html =~ "Reported"
  end

  test "logged-in users can report a package from the header dialog", %{conn: conn} do
    %{conn: conn, user: user} = register_and_log_in_user(%{conn: conn})
    package = package_fixture(user_scope_fixture())

    {:ok, lv, html} = live(conn, ~p"/package/#{package.name}")

    assert has_element?(lv, "button[aria-label='Report package']")
    assert has_element?(lv, "#report_package_modal form[phx-submit='report_package']")
    refute has_element?(lv, "#package-report")
    assert html =~ "Choose a reason"

    html =
      lv
      |> element("#report_package_modal form[phx-submit='report_package']")
      |> render_submit(%{"reason" => "spam", "details" => "This is spam"})

    assert html =~ "Report submitted. A moderator will review it."
    assert html =~ "Reported"
    refute has_element?(lv, "#report_package_modal")
    refute has_element?(lv, "button[aria-label='Report package']")
    assert [report] = Moderation.list_reports()
    assert report.reporter_id == user.id
  end

  test "users with an open report see a reported badge", %{conn: conn} do
    %{conn: conn, user: user} = register_and_log_in_user(%{conn: conn})
    package = package_fixture(user_scope_fixture())
    report_fixture(user, package)

    {:ok, lv, html} = live(conn, ~p"/package/#{package.name}")

    assert html =~ "Reported"
    assert has_element?(lv, "span[title='You already have an open report for this package.']")
    refute has_element?(lv, "button[aria-label='Report package']")
    refute has_element?(lv, "#report_package_modal")
  end

  test "report submissions are rate limited per user", %{conn: conn} do
    %{conn: conn, user: user} = register_and_log_in_user(%{conn: conn})
    package = package_fixture(user_scope_fixture())
    key = "user:report:#{user.id}"

    for _ <- 1..5 do
      assert {:allow, _count} = RateLimit.hit(:report, key)
    end

    {:ok, lv, _html} = live(conn, ~p"/package/#{package.name}")

    html =
      lv
      |> element("#report_package_modal form[phx-submit='report_package']")
      |> render_submit(%{"reason" => "spam"})

    assert html =~ "Too many reports. Try again later."
    assert Moderation.list_reports() == []
  end

  test "shows license, Lua, platforms, build and updated date", %{conn: conn} do
    scope = user_scope_fixture()
    package = package_fixture(scope)

    release_fixture(scope, package,
      metadata: %{
        "license" => "MIT",
        "lua" => ">= 5.1",
        "platforms" => ["linux", "macosx", "!windows"],
        "build_type" => "cmake"
      }
    )

    {:ok, lv, html} = live(conn, ~p"/package/#{package.name}")

    assert html =~ ">License<"
    assert html =~ "MIT"
    assert html =~ ">Lua<"
    assert html =~ "&gt;= 5.1"
    assert html =~ ">Platforms<"
    assert html =~ "Linux, macOS"
    refute html =~ "Not Windows"
    assert html =~ ">Build<"
    assert html =~ "cmake"
    assert html =~ ">Updated<"
    refute html =~ ">Created<"
    refute html =~ ">Package Name<"
    assert has_element?(lv, "h3", "Package Overview")
  end

  test "hides missing metadata rows and omits the builtin build type", %{conn: conn} do
    scope = user_scope_fixture()
    package = package_fixture(scope)

    release_fixture(scope, package,
      metadata: %{"build_type" => "builtin", "platforms" => ["!windows"]}
    )

    {:ok, _lv, html} = live(conn, ~p"/package/#{package.name}")

    refute html =~ ">License<"
    refute html =~ ">Lua<"
    refute html =~ ">Platforms<"
    refute html =~ ">Build<"
    assert html =~ ">Updated<"
  end
end
