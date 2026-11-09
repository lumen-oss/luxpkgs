defmodule Luxpkgs.ModerationTest do
  use Luxpkgs.DataCase

  import Luxpkgs.AccountsFixtures
  import Luxpkgs.AdminFixtures
  import Luxpkgs.ModerationFixtures
  import Luxpkgs.PackagesFixtures

  alias Luxpkgs.Audit
  alias Luxpkgs.Moderation
  alias Luxpkgs.Moderation.Report
  alias Luxpkgs.Packages.Package
  alias Luxpkgs.Repo

  defp set_status!(package, status) do
    package
    |> Ecto.Changeset.change(status: status)
    |> Repo.update!()
  end

  test "create_report/3 opens a report for an active package" do
    scope = user_scope_fixture()
    package = package_fixture(scope)
    reporter = user_fixture()

    assert {:ok, %Report{} = report} =
             Moderation.create_report(reporter, package, %{
               "reason" => "spam",
               "details" => "Looks like spam"
             })

    assert report.status == :open
    assert report.reason == :spam
    assert report.details == "Looks like spam"
    assert report.package_id == package.id
    assert report.reporter_id == reporter.id
    assert Moderation.open_report?(reporter, package)
  end

  test "create_report/3 rejects a second open report from the same user" do
    scope = user_scope_fixture()
    package = package_fixture(scope)
    reporter = user_fixture()
    report_fixture(reporter, package)

    assert {:error, :already_open} =
             Moderation.create_report(reporter, package, %{"reason" => "broken"})
  end

  test "the database rejects duplicate open reports" do
    scope = user_scope_fixture()
    package = package_fixture(scope)
    reporter = user_fixture()
    report_fixture(reporter, package)

    assert {:error, %Ecto.Changeset{} = changeset} =
             %Report{}
             |> Report.changeset(%{
               package_id: package.id,
               reporter_id: reporter.id,
               reason: :spam
             })
             |> Repo.insert()

    assert {"already has an open report", _opts} = changeset.errors[:package_id]
  end

  test "different users can report the same package" do
    scope = user_scope_fixture()
    package = package_fixture(scope)
    first = user_fixture()
    second = user_fixture()

    assert {:ok, _report} = Moderation.create_report(first, package, %{"reason" => "spam"})
    assert {:ok, _report} = Moderation.create_report(second, package, %{"reason" => "spam"})
  end

  test "create_report/3 rejects non-active packages" do
    scope = user_scope_fixture()
    package = package_fixture(scope) |> set_status!(:hidden)

    assert {:error, :inactive_package} =
             Moderation.create_report(user_fixture(), package, %{"reason" => "spam"})
  end

  test "create_report/3 validates the reason and details length" do
    scope = user_scope_fixture()
    package = package_fixture(scope)
    reporter = user_fixture()

    assert {:error, %Ecto.Changeset{}} =
             Moderation.create_report(reporter, package, %{"reason" => "bogus"})

    assert {:error, %Ecto.Changeset{errors: errors}} =
             Moderation.create_report(reporter, package, %{
               "reason" => "spam",
               "details" => String.duplicate("a", 2001)
             })

    assert errors[:details]
  end

  test "resolve_report/3 requires a note and records an audit event" do
    scope = user_scope_fixture()
    package = package_fixture(scope)
    report = report_fixture(user_fixture(), package)
    admin = admin_fixture(%{role: :moderator})

    assert {:error, :note_required} = Moderation.resolve_report(admin, report, "  ")

    assert {:ok, resolved} = Moderation.resolve_report(admin, report, " Handled ")
    assert resolved.status == :resolved
    assert resolved.resolution_note == "Handled"
    assert resolved.resolved_by_admin_id == admin.id
    assert resolved.resolved_at

    assert [event] = Audit.list_events()
    assert event.action == "report.resolved"
    assert event.type == :report
    assert event.target_id == report.id
    assert event.metadata["note"] == "Handled"
  end

  test "dismiss_report/3 requires a note and records an audit event" do
    scope = user_scope_fixture()
    package = package_fixture(scope)
    report = report_fixture(user_fixture(), package)
    admin = admin_fixture(%{role: :moderator})

    assert {:error, :note_required} = Moderation.dismiss_report(admin, report, nil)

    assert {:ok, dismissed} = Moderation.dismiss_report(admin, report, "Not a violation")
    assert dismissed.status == :dismissed

    assert [event] = Audit.list_events()
    assert event.action == "report.dismissed"
  end

  test "warn_report/3 appends a moderation note, keeps the report open and audits" do
    scope = user_scope_fixture()
    package = package_fixture(scope)
    package = Ecto.Changeset.change(package, moderation_note: "Existing note") |> Repo.update!()
    report = report_fixture(user_fixture(), package)
    admin = admin_fixture(%{role: :moderator})

    assert {:error, :note_required} = Moderation.warn_report(admin, report, "")

    assert {:ok, %Package{} = warned} = Moderation.warn_report(admin, report, "Be civil")
    assert warned.moderation_note == "Existing note\n\nReport warning: Be civil"
    assert Repo.get!(Report, report.id).status == :open

    assert [event] = Audit.list_events()
    assert event.action == "report.warned"
    assert event.metadata["note"] == "Be civil"
  end

  test "closed reports cannot be resolved twice" do
    scope = user_scope_fixture()
    package = package_fixture(scope)
    report = report_fixture(user_fixture(), package)
    admin = admin_fixture(%{role: :admin})

    assert {:ok, _report} = Moderation.resolve_report(admin, report, "Done")
    assert {:error, :not_open} = Moderation.dismiss_report(admin, report, "Nope")
  end

  test "list_reports/1 orders oldest first and filters" do
    scope = user_scope_fixture()
    package = package_fixture(scope, %{name: "reported_package"})
    other_package = package_fixture(scope, %{name: "other_package"})
    first = report_fixture(user_fixture(), package, %{reason: :spam})
    second = report_fixture(user_fixture(), other_package, %{reason: :broken})

    assert Enum.map(Moderation.list_reports(), & &1.id) == [first.id, second.id]

    assert Enum.map(Moderation.list_reports(reason: "broken"), & &1.id) == [second.id]
    assert Enum.map(Moderation.list_reports(package: "reported"), & &1.id) == [first.id]

    assert Moderation.list_reports(from: Date.utc_today(), to: Date.utc_today())
           |> Enum.map(& &1.id) == [first.id, second.id]
  end
end
