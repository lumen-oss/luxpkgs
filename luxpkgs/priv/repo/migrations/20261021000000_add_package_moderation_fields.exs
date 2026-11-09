defmodule Luxpkgs.Repo.Migrations.AddPackageModerationFields do
  use Ecto.Migration

  def change do
    alter table(:packages) do
      add :status, :string, null: false, default: "active"
      add :moderation_note, :text
      add :featured_at, :utc_datetime
    end

    create index(:packages, [:status])
    create index(:packages, [:featured_at])

    create constraint(
             :packages,
             :packages_status_must_be_valid,
             check: "status IN ('active', 'hidden')"
           )
  end
end
