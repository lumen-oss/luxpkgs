defmodule Luxpkgs.Repo.Migrations.CreatePackageReports do
  use Ecto.Migration

  def change do
    create table(:package_reports) do
      add :package_id, references(:packages, on_delete: :delete_all), null: false
      add :reporter_id, references(:users, on_delete: :nilify_all)
      add :reason, :string, null: false
      add :details, :text
      add :status, :string, null: false, default: "open"
      add :resolution_note, :text
      add :resolved_by_admin_id, references(:admins, on_delete: :nilify_all)
      add :resolved_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create index(:package_reports, [:package_id])
    create index(:package_reports, [:reporter_id])
    create index(:package_reports, [:status, :inserted_at])

    create index(:package_reports, [:package_id, :reporter_id],
             unique: true,
             where: "status = 'open'",
             name: :package_reports_open_unique
           )

    create constraint(
             :package_reports,
             :package_reports_reason_must_be_valid,
             check: "reason IN ('malicious', 'spam', 'copyright', 'broken', 'other')"
           )

    create constraint(
             :package_reports,
             :package_reports_status_must_be_valid,
             check: "status IN ('open', 'resolved', 'dismissed')"
           )
  end
end
