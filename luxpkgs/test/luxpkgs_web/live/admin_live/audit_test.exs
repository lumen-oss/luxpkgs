defmodule LuxpkgsWeb.AdminLive.AuditTest do
  use LuxpkgsWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Luxpkgs.AccountsFixtures
  import Luxpkgs.AdminFixtures

  alias Luxpkgs.Audit

  defp admin_conn(conn, role, verified_at \\ System.os_time(:second)) do
    user = user_fixture()
    admin_fixture(%{user: user, role: role})

    conn
    |> log_in_user(user)
    |> put_session(:admin_totp_verified_at, verified_at)
  end

  defp event!(attrs) do
    {:ok, event} =
      Audit.record(
        Map.merge(
          %{type: :system, action: "system.test", actor_label: "system"},
          attrs
        )
      )

    event
  end

  defp at!(event, datetime) do
    event
    |> Ecto.Changeset.change(inserted_at: datetime)
    |> Luxpkgs.Repo.update!()
  end

  test "redirects non-admins", %{conn: conn} do
    user = user_fixture()

    conn =
      conn
      |> log_in_user(user)
      |> put_session(:admin_totp_verified_at, System.os_time(:second))

    assert {:error, {:redirect, %{to: "/"}}} = live(conn, ~p"/admin/audit")
  end

  test "redirects moderators with a permission flash", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/admin", flash: flash}}} =
             live(admin_conn(conn, :moderator), ~p"/admin/audit")

    assert flash["error"] == "You do not have permission to view the audit log."
  end

  test "lists events newest first", %{conn: conn} do
    event!(%{
      type: :package,
      action: "package.hidden",
      actor_label: "admin",
      target_type: "package",
      target_id: 1,
      target_label: "older-target"
    })

    event!(%{
      type: :report,
      action: "report.resolved",
      actor_label: "moderator",
      target_type: "report",
      target_id: 2,
      target_label: "newer-target",
      metadata: %{"note" => "resolved"}
    })

    {:ok, _lv, html} = live(admin_conn(conn, :admin), ~p"/admin/audit")

    assert html =~ "Audit log"
    assert html =~ "older-target"
    assert html =~ "newer-target"
    assert :binary.match(html, "newer-target") < :binary.match(html, "older-target")
    assert html =~ "Live"
    assert html =~ "2 loaded"
  end

  test "filters by type, actor, and search", %{conn: conn} do
    event!(%{
      type: :package,
      action: "package.hidden",
      actor_label: "admin",
      target_type: "package",
      target_id: 1,
      target_label: "package-target"
    })

    event!(%{
      type: :report,
      action: "report.resolved",
      actor_label: "moderator",
      target_type: "report",
      target_id: 2,
      target_label: "report-target",
      metadata: %{"note" => "needle-note"}
    })

    conn = admin_conn(conn, :admin)

    {:ok, _lv, html} = live(conn, ~p"/admin/audit?type=report")
    assert html =~ "report-target"
    refute html =~ "package-target"

    {:ok, _lv, html} = live(conn, ~p"/admin/audit?q=needle")
    assert html =~ "report-target"
    refute html =~ "package-target"

    {:ok, _lv, html} = live(conn, ~p"/admin/audit?actor=moder")
    assert html =~ "report-target"
    refute html =~ "package-target"
  end

  test "filters by date", %{conn: conn} do
    event!(%{
      type: :system,
      action: "system.today",
      actor_label: "system",
      target_label: "today-target"
    })

    conn = admin_conn(conn, :admin)
    today = Date.utc_today() |> Date.to_iso8601()
    yesterday = Date.utc_today() |> Date.add(-1) |> Date.to_iso8601()

    {:ok, _lv, html} = live(conn, ~p"/admin/audit?from=#{today}")
    assert html =~ "today-target"

    {:ok, _lv, html} = live(conn, ~p"/admin/audit?to=#{yesterday}")
    assert html =~ "No audit events match these filters."
    refute html =~ "today-target"
  end

  test "renders metadata details", %{conn: conn} do
    event!(%{
      type: :package,
      action: "package.hidden",
      actor_label: "admin",
      target_type: "package",
      target_id: 1,
      target_label: "alpha",
      metadata: %{
        "from" => "active",
        "to" => "hidden",
        "note" => "Testing note",
        "package_id" => 189
      }
    })

    {:ok, _lv, html} = live(admin_conn(conn, :admin), ~p"/admin/audit")

    assert html =~ "Details"
    assert html =~ "Testing note"
    assert html =~ "active"
    assert html =~ "hidden"
    assert html =~ ~r/<pre[^>]*>189<\/pre>/
    assert html =~ ~r/<p[^>]*>Testing note<\/p>/
    refute html =~ "No metadata."
  end

  test "groups days in descending date order", %{conn: conn} do
    oldest = event!(%{action: "system.oldest", target_label: "oldest-day"})
    newest = event!(%{action: "system.newest", target_label: "newest-day"})
    middle = event!(%{action: "system.middle", target_label: "middle-day"})

    at!(oldest, ~U[2026-10-20 20:35:43.000000Z])
    at!(newest, ~U[2026-11-07 01:04:17.000000Z])
    at!(middle, ~U[2026-11-06 18:12:39.000000Z])

    {:ok, _lv, html} = live(admin_conn(conn, :admin), ~p"/admin/audit")

    newest_at = :binary.match(html, "newest-day") |> elem(0)
    middle_at = :binary.match(html, "middle-day") |> elem(0)
    oldest_at = :binary.match(html, "oldest-day") |> elem(0)

    assert newest_at < middle_at
    assert middle_at < oldest_at
  end

  test "updates filters through the form", %{conn: conn} do
    event!(%{
      type: :report,
      action: "report.resolved",
      actor_label: "moderator",
      target_type: "report",
      target_id: 1,
      target_label: "report-target"
    })

    event!(%{
      type: :package,
      action: "package.hidden",
      actor_label: "admin",
      target_type: "package",
      target_id: 2,
      target_label: "package-target"
    })

    {:ok, lv, _html} = live(admin_conn(conn, :admin), ~p"/admin/audit")

    html =
      lv
      |> element("#admin-audit-filters")
      |> render_change(%{
        "type" => "report",
        "q" => "",
        "action" => "all",
        "actor" => "",
        "target_type" => "all",
        "from" => "",
        "to" => ""
      })

    assert html =~ "report-target"
    refute html =~ "package-target"
  end

  test "prepends new matching events", %{conn: conn} do
    event!(%{
      type: :system,
      action: "system.old",
      actor_label: "system",
      target_label: "old-target"
    })

    {:ok, lv, _html} = live(admin_conn(conn, :admin), ~p"/admin/audit")

    event!(%{
      type: :system,
      action: "system.new",
      actor_label: "system",
      target_label: "new-target"
    })

    html = render(lv)
    assert html =~ "new-target"
    assert html =~ "old-target"
  end

  test "ignores live events that do not match the filters", %{conn: conn} do
    event!(%{
      type: :report,
      action: "report.resolved",
      actor_label: "moderator",
      target_type: "report",
      target_id: 1,
      target_label: "matching-report",
      metadata: %{"note" => "ok"}
    })

    {:ok, lv, html} = live(admin_conn(conn, :admin), ~p"/admin/audit?type=report")
    assert html =~ "matching-report"

    event!(%{
      type: :package,
      action: "package.hidden",
      actor_label: "admin",
      target_type: "package",
      target_id: 2,
      target_label: "ignored-package"
    })

    html = render(lv)
    refute html =~ "ignored-package"
    assert html =~ "matching-report"

    event!(%{
      type: :report,
      action: "report.dismissed",
      actor_label: "moderator",
      target_type: "report",
      target_id: 3,
      target_label: "new-report",
      metadata: %{"note" => "dismissed"}
    })

    html = render(lv)
    assert html =~ "new-report"
  end

  test "loads older events in pages", %{conn: conn} do
    event!(%{
      type: :system,
      action: "system.one",
      actor_label: "system",
      target_label: "first-target"
    })

    event!(%{
      type: :system,
      action: "system.two",
      actor_label: "system",
      target_label: "second-target"
    })

    conn = admin_conn(conn, :admin)

    {:ok, lv, html} = live(conn, ~p"/admin/audit?limit=1")
    assert html =~ "second-target"
    refute html =~ "first-target"
    assert has_element?(lv, "a", "Load older events")

    {:ok, _lv, html} = live(conn, ~p"/admin/audit?limit=200")
    assert html =~ "second-target"
    assert html =~ "first-target"
  end

  test "shows the audit link only to admins", %{conn: conn} do
    {:ok, _lv, html} = live(admin_conn(conn, :admin), ~p"/admin/audit")

    assert html =~ ~s(href="/admin/audit")
    assert html =~ ~s(aria-current="page")

    {:ok, _lv, html} = live(admin_conn(conn, :moderator), ~p"/admin")

    refute html =~ ~s(href="/admin/audit")
  end

  test "renders empty states", %{conn: conn} do
    conn = admin_conn(conn, :admin)

    {:ok, _lv, html} = live(conn, ~p"/admin/audit")
    assert html =~ "No audit events recorded yet."

    {:ok, _lv, html} = live(conn, ~p"/admin/audit?type=report")
    assert html =~ "No audit events match these filters."
    assert html =~ "Clear filters"
  end

  test "highlights the active quick range", %{conn: conn} do
    conn = admin_conn(conn, :admin)

    {:ok, lv, _html} = live(conn, ~p"/admin/audit")
    assert has_element?(lv, "a.btn-primary", "All")

    seven_days_ago = Date.utc_today() |> Date.add(-7) |> Date.to_iso8601()
    {:ok, lv, _html} = live(conn, ~p"/admin/audit?from=#{seven_days_ago}")

    assert has_element?(lv, "a.btn-primary", "7d")
  end
end
