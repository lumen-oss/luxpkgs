defmodule LuxpkgsWeb.AdminLive.ReportsTest do
  use LuxpkgsWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Luxpkgs.AccountsFixtures
  import Luxpkgs.AdminFixtures
  import Luxpkgs.ModerationFixtures
  import Luxpkgs.PackagesFixtures

  alias Luxpkgs.Audit
  alias Luxpkgs.Moderation
  alias Luxpkgs.Packages.Package
  alias Luxpkgs.Repo

  defp admin_conn(conn, role, verified_at \\ System.os_time(:second)) do
    user = user_fixture()
    admin_fixture(%{user: user, role: role})

    conn
    |> log_in_user(user)
    |> put_session(:admin_totp_verified_at, verified_at)
  end

  defp report_setup do
    scope = user_scope_fixture()
    package = package_fixture(scope)
    report = report_fixture(user_fixture(), package)
    {package, report}
  end

  test "redirects non-admins", %{conn: conn} do
    user = user_fixture()

    conn =
      conn
      |> log_in_user(user)
      |> put_session(:admin_totp_verified_at, System.os_time(:second))

    assert {:error, {:redirect, %{to: "/"}}} = live(conn, ~p"/admin/reports")
  end

  test "lists open reports oldest first", %{conn: conn} do
    scope = user_scope_fixture()
    first_package = package_fixture(scope, %{name: "first_reported"})
    second_package = package_fixture(scope, %{name: "second_reported"})
    first = report_fixture(user_fixture(), first_package)
    second = report_fixture(user_fixture(), second_package)

    {:ok, _lv, html} = live(admin_conn(conn, :moderator), ~p"/admin/reports")

    assert html =~ "first_reported"
    assert html =~ "second_reported"
    assert :binary.match(html, "first_reported") < :binary.match(html, "second_reported")
    assert html =~ ~s(id="report-#{first.id}")
    assert html =~ ~s(id="report-#{second.id}")
  end

  test "filters reports by reason and package", %{conn: conn} do
    scope = user_scope_fixture()
    spam_package = package_fixture(scope, %{name: "spam_report"})
    broken_package = package_fixture(scope, %{name: "broken_report"})
    report_fixture(user_fixture(), spam_package, %{reason: :spam})
    report_fixture(user_fixture(), broken_package, %{reason: :broken})

    conn = admin_conn(conn, :moderator)

    {:ok, _lv, html} = live(conn, ~p"/admin/reports?reason=broken")
    assert html =~ "broken_report"
    refute html =~ "spam_report"

    {:ok, _lv, html} = live(conn, ~p"/admin/reports?package=spam")
    assert html =~ "spam_report"
    refute html =~ "broken_report"
  end

  test "resolving requires a note and records an audit event", %{conn: conn} do
    {_package, report} = report_setup()
    {:ok, lv, _html} = live(admin_conn(conn, :moderator), ~p"/admin/reports")

    html =
      lv
      |> element("#report-#{report.id} form")
      |> render_submit(%{"report_id" => report.id, "action" => "resolve", "note" => ""})

    assert html =~ "Add a note before taking this action."
    assert Moderation.get_report(report.id).status == :open

    html =
      lv
      |> element("#report-#{report.id} form")
      |> render_submit(%{"report_id" => report.id, "action" => "resolve", "note" => "Handled"})

    assert html =~ "Report resolved."
    refute html =~ ~s(id="report-#{report.id}")
    assert Moderation.get_report(report.id).status == :resolved

    assert [event] = Audit.list_events()
    assert event.action == "report.resolved"
    assert event.target_id == report.id
  end

  test "dismissing requires a note", %{conn: conn} do
    {_package, report} = report_setup()
    {:ok, lv, _html} = live(admin_conn(conn, :moderator), ~p"/admin/reports")

    html =
      lv
      |> element("#report-#{report.id} form")
      |> render_submit(%{
        "report_id" => report.id,
        "action" => "dismiss",
        "note" => "No violation"
      })

    assert html =~ "Report dismissed."
    assert Moderation.get_report(report.id).status == :dismissed
  end

  test "warning records a note and leaves the report open", %{conn: conn} do
    {package, report} = report_setup()
    {:ok, lv, _html} = live(admin_conn(conn, :moderator), ~p"/admin/reports")

    html =
      lv
      |> element("#report-#{report.id} form")
      |> render_submit(%{"report_id" => report.id, "action" => "warn", "note" => "Be civil"})

    assert html =~ "Warning added to the package moderation note."
    assert html =~ "Package moderation note:"
    assert html =~ "Report warning: Be civil"
    assert Moderation.get_report(report.id).status == :open
    assert Repo.get!(Package, package.id).moderation_note =~ "Report warning: Be civil"

    assert [event] = Audit.list_events()
    assert event.action == "report.warned"
  end

  test "hiding a package leaves the report open", %{conn: conn} do
    {package, report} = report_setup()
    {:ok, lv, _html} = live(admin_conn(conn, :moderator), ~p"/admin/reports")

    html =
      lv
      |> element("#report-#{report.id} button[phx-click='hide_package']")
      |> render_click()

    assert html =~ "Package hidden. The report remains open."
    assert Repo.get!(Package, package.id).status == :hidden
    assert Moderation.get_report(report.id).status == :open
  end

  test "admins can remove a package from the queue", %{conn: conn} do
    {package, report} = report_setup()
    {:ok, lv, _html} = live(admin_conn(conn, :admin), ~p"/admin/reports")

    html =
      lv
      |> element("#report-#{report.id} button[phx-click='remove_package']")
      |> render_click()

    assert html =~ "Package removed. The report remains open."
    assert Repo.get!(Package, package.id).status == :removed
    assert Moderation.get_report(report.id).status == :open
  end

  test "moderators do not see remove package", %{conn: conn} do
    {_package, report} = report_setup()
    {:ok, lv, _html} = live(admin_conn(conn, :moderator), ~p"/admin/reports")

    refute has_element?(lv, "#report-#{report.id} button[phx-click='remove_package']")
    assert has_element?(lv, "#report-#{report.id} button[phx-click='hide_package']")
  end

  test "removing a package requires a fresh second factor", %{conn: conn} do
    {package, report} = report_setup()
    conn = admin_conn(conn, :admin, System.os_time(:second) - 601)
    {:ok, lv, _html} = live(conn, ~p"/admin/reports")

    assert {:error, {:redirect, %{to: "/admin/verify"}}} =
             lv
             |> element("#report-#{report.id} button[phx-click='remove_package']")
             |> render_click()

    assert Repo.get!(Package, package.id).status == :active
  end
end
